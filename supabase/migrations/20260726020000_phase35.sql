-- Migration : Phase 3.5 -- identité civile privée, réponses aux commentaires
-- (profondeur 1), bannière de profil, couverture de playlist, suggestions de
-- clips. RLS activée dès la création de chaque table, politiques nommées,
-- GRANT explicite, fonctions SECURITY DEFINER verrouillées (search_path vide
-- + revoke/grant ciblé). Référence : docs/ARCHITECTURE.md §3 et §4.

-- =============================================================================
-- 1) user_identities -- noms civils (prénom/nom légal, post-nom), séparés de
--    `profiles`.
--
--    RAISON CRITIQUE : `profiles_select_public` (20260725010000) est
--    `using (true)`, y compris pour `anon`. Toute colonne ajoutée directement
--    à `profiles` serait donc publiquement lisible. Les noms civils sont une
--    donnée sensible (voir docs/ARCHITECTURE.md §4, identité) -- ils vivent
--    dans une table séparée, lisible/écrivable UNIQUEMENT par son
--    propriétaire. Aucune politique `anon`, aucune politique admin (pas
--    nécessaire à ce stade : la vérification d'artiste, Phase 4, passera par
--    une Edge Function service_role).
-- =============================================================================
create table public.user_identities (
  user_id           uuid primary key references auth.users (id) on delete cascade,
  legal_first_name  text not null
                    check (char_length(btrim(legal_first_name)) between 1 and 80),
  legal_last_name   text not null
                    check (char_length(btrim(legal_last_name)) between 1 and 80),
  -- Post-nom (usage courant en RDC/Afrique centrale) : optionnel.
  legal_middle_name text
                    check (legal_middle_name is null or char_length(btrim(legal_middle_name)) between 1 and 80),
  updated_at        timestamptz not null default now()
);

comment on table public.user_identities is
  'Noms civils (identité légale) d''un utilisateur, séparés de public.profiles '
  'car profiles_select_public est lisible par anon. Aucune politique anon ici : '
  'lecture/écriture strictement réservées au propriétaire (auth.uid() = user_id).';

-- ---------------------------------------------------------------------------
-- Garde-fou : updated_at posé automatiquement, jamais fourni par le client
-- (même patron que comments_guard_client_fields / playlists_guard_client_fields).
-- ---------------------------------------------------------------------------
create or replace function public.user_identities_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  new.updated_at := now();

  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
  end if;

  return new;
end;
$$;

comment on function public.user_identities_guard_client_fields() is
  'Verrouille user_id à l''UPDATE et pose updated_at automatiquement.';

create trigger user_identities_guard_client_fields_trigger
  before insert or update on public.user_identities
  for each row
  execute function public.user_identities_guard_client_fields();

revoke execute on function public.user_identities_guard_client_fields() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS -- propriétaire uniquement, aucune politique anon.
-- ---------------------------------------------------------------------------
alter table public.user_identities enable row level security;

create policy user_identities_select_own
  on public.user_identities
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy user_identities_insert_own
  on public.user_identities
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy user_identities_update_own
  on public.user_identities
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Pas de politique DELETE : la suppression suit le cycle de vie du compte
-- (on delete cascade depuis auth.users), pas une action cliente isolée.

grant select, insert, update on public.user_identities to authenticated;

-- =============================================================================
-- 2) comments.parent_id -- réponses, UN SEUL niveau de profondeur.
--
--    Choix : trigger (pas de contrainte CHECK, qui ne peut pas lire d'autres
--    lignes) qui vérifie que le parent existe, appartient au même video_id, et
--    que le parent est lui-même un commentaire racine (parent_id is null).
--    parent_id est figé après création, comme author_id/video_id/created_at.
--
--    Impact sur comment_count : LES RÉPONSES COMPTENT dans
--    videos.comment_count. Aucune modification du trigger de compteur
--    (`comments_maintain_video_comment_count`) n'est nécessaire : il
--    s'applique déjà à TOUTE ligne insérée/soft-deletée dans `comments`, sans
--    distinguer racine/réponse -- c'est le comportement voulon (un fil avec
--    des réponses doit afficher un total qui inclut les réponses).
-- =============================================================================
alter table public.comments
  add column if not exists parent_id uuid references public.comments (id) on delete cascade;

comment on column public.comments.parent_id is
  'Commentaire parent (réponse). Un seul niveau de profondeur : le parent doit '
  'lui-même avoir parent_id NULL (vérifié par comments_guard_client_fields). '
  'Figé après création. Compte dans videos.comment_count comme tout commentaire.';

-- Fil de réponses d'un commentaire racine, plus anciennes d'abord.
create index if not exists comments_parent_created_idx
  on public.comments (parent_id, created_at)
  where parent_id is not null;

-- ---------------------------------------------------------------------------
-- Extension du garde-fou existant (MODIFICATION, pas duplication) :
-- comments_guard_client_fields() gagne la vérification de profondeur à
-- l'INSERT et le verrouillage de parent_id à l'UPDATE. PAS SECURITY DEFINER
-- (inchangé) : le SELECT sur le parent passe par la RLS de l'appelant --
-- cohérent, un parent invisible pour l'appelant n'a de toute façon aucune
-- raison d'être un parent valide.
-- ---------------------------------------------------------------------------
create or replace function public.comments_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_video_id  uuid;
  v_parent_parent_id uuid;
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.updated_at := now();
    new.deleted_at := null;

    if new.parent_id is not null then
      select c.video_id, c.parent_id
        into v_parent_video_id, v_parent_parent_id
        from public.comments c
       where c.id = new.parent_id;

      if v_parent_video_id is null then
        raise exception 'Commentaire parent introuvable.'
          using errcode = '22023';
      end if;

      if v_parent_video_id is distinct from new.video_id then
        raise exception 'Le commentaire parent doit appartenir au même clip.'
          using errcode = '22023';
      end if;

      if v_parent_parent_id is not null then
        raise exception
          'Une réponse ne peut pas elle-même être répondue (profondeur 1 max).'
          using errcode = '22023';
      end if;
    end if;

    return new;
  end if;

  -- UPDATE côté client : author_id, video_id, created_at, parent_id sont
  -- immuables ; updated_at est posé automatiquement.
  new.author_id := old.author_id;
  new.video_id := old.video_id;
  new.created_at := old.created_at;
  new.parent_id := old.parent_id;
  new.updated_at := now();

  return new;
end;
$$;

comment on function public.comments_guard_client_fields() is
  'Verrouille author_id/video_id/created_at/parent_id à l''écriture côté client ; '
  'pose updated_at automatiquement ; impose la profondeur 1 max et la '
  'cohérence video_id du parent à l''INSERT.';

-- Le trigger existant pointe déjà vers cette fonction (create or replace
-- suffit, pas de nouveau trigger à créer).

-- =============================================================================
-- 3) profiles.banner_path -- bannière de profil.
--
--    Bucket réutilisé : `avatars`, convention `<uid>/banner.<ext>`.
--    AUCUNE politique storage ajoutée : les 4 politiques existantes de
--    20260724010200_storage_avatars.sql / 20260725010000_profiles_public_read.sql
--    filtrent uniquement sur `bucket_id = 'avatars'` et, pour l'écriture, sur
--    `(storage.foldername(name))[1] = auth.uid()::text` -- elles ne
--    contraignent PAS le nom de fichier après le premier segment. Un chemin
--    `<uid>/banner.<ext>` est donc déjà couvert : lecture par
--    `avatars_select_all` (tout le monde, bucket public par nature depuis la
--    Phase 3), écriture par `avatars_insert_own` / `avatars_update_own` /
--    `avatars_delete_own` (propriétaire du dossier). Vérifié ligne par ligne
--    avant d'écrire cette migration.
-- =============================================================================
alter table public.profiles
  add column if not exists banner_path text;

comment on column public.profiles.banner_path is
  'Chemin (pas une URL) dans le bucket avatars, convention <uid>/banner.<ext>. '
  'Aucune politique storage supplémentaire nécessaire (voir commentaire ci-dessus).';

-- `profiles_update_own` autorise déjà la modification de sa propre ligne ;
-- banner_path n'est ni un compteur ni un champ sensible, aucun garde-fou
-- supplémentaire n'est nécessaire (même traitement que avatar_url, bio, etc.).

-- =============================================================================
-- 4) playlists.cover_path -- couverture de playlist.
--
--    BUCKET DÉDIÉ `playlist-covers` (privé), et non réutilisation du bucket
--    `avatars` : `avatars_select_all` ouvre la lecture à TOUT LE MONDE sur tout
--    le bucket, sans condition -- une playlist PRIVÉE (is_public = false) ne
--    doit pourtant pas exposer sa couverture publiquement. La politique de
--    lecture doit donc être conditionnée à `playlists.is_public` (ou à la
--    propriété), ce qu'un bucket partagé avec les avatars ne permettrait pas
--    sans réécrire les politiques `avatars_*` (et donc changer le
--    comportement des avatars, hors périmètre). D'où un bucket séparé, calqué
--    sur le patron `videos_storage_select_published` (jointure
--    storage.objects.name -> table métier).
-- =============================================================================
alter table public.playlists
  add column if not exists cover_path text;

comment on column public.playlists.cover_path is
  'Chemin (pas une URL) dans le bucket privé playlist-covers, convention '
  '<uid>/<playlist_id>.<ext>. Lecture conditionnée à playlists.is_public ou à '
  'la propriété (voir playlist_covers_storage_select_visible).';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'playlist-covers',
  'playlist-covers',
  false,
  5242880, -- 5 Mo, même plafond que avatars
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do nothing;

-- Écriture : uniquement dans son propre dossier (même patron que avatars).
create policy playlist_covers_storage_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'playlist-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy playlist_covers_storage_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'playlist-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'playlist-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy playlist_covers_storage_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'playlist-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Lecture : le propriétaire du dossier (prévisualisation avant publication de
-- la playlist), OU tout le monde (anon inclus) si l'objet est rattaché à une
-- playlist `is_public`. Calqué sur `videos_storage_select_published`.
create policy playlist_covers_storage_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'playlist-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- La condition `(storage.foldername(name))[1] = p.owner_id::text` n'est PAS
-- décorative : sans elle, l'égalité de texte `p.cover_path = name` suffit à
-- débloquer la lecture, quelle que soit la playlist qui porte ce chemin.
-- Scénario réel, trouvé à l'audit : A publie une playlist, son `cover_path`
-- devient lisible par tout le monde (la ligne est publique), puis A repasse la
-- playlist en privé. B écrit alors ce même chemin dans SA playlist — rien ne
-- l'en empêche, `playlists_update_own` ne contrôle que `owner_id` — la rend
-- publique, et l'image privée de A redevient téléchargeable par n'importe qui,
-- définitivement. Exiger que le dossier appartienne au propriétaire de la
-- playlist qui débloque coupe ce détournement à la racine.
create policy playlist_covers_storage_select_visible
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'playlist-covers'
    and exists (
      select 1
      from public.playlists p
      where p.cover_path = storage.objects.name
        and p.is_public
        and (storage.foldername(storage.objects.name))[1] = p.owner_id::text
    )
  );

-- ---------------------------------------------------------------------------
-- Défense en profondeur : `cover_path` est verrouillé à l'ÉCRITURE.
--
-- La politique ci-dessus suffit à empêcher la fuite, mais une colonne texte
-- libre pointant sur le stockage d'autrui reste une arme chargée : la
-- prochaine politique écrite sur ce bucket pourrait oublier la condition. On
-- refuse donc, dès l'écriture, tout chemin dont le premier segment n'est pas
-- le dossier du propriétaire.
--
-- `split_part` plutôt que `storage.foldername` : c'est une fonction du
-- catalogue, toujours résolvable malgré `search_path = ''`, sans dépendre des
-- droits d'exécution du schéma `storage`.
--
-- La comparaison porte sur `new.owner_id` et non sur `auth.uid()` : à
-- l'INSERT, `playlists_insert_own` impose déjà `owner_id = auth.uid()`, et à
-- l'UPDATE ce trigger vient de forcer `new.owner_id := old.owner_id`. Passer
-- par la colonne reste donc correct tout en fonctionnant aussi pour un appel
-- serveur légitime.
-- ---------------------------------------------------------------------------
create or replace function public.playlists_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.item_count := 0;
    new.created_at := now();
    new.updated_at := now();
  else
    new.item_count := old.item_count;
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;

  if new.cover_path is not null
     and pg_catalog.split_part(new.cover_path, '/', 1)
         is distinct from new.owner_id::text then
    raise exception
      'La couverture doit être stockée dans le dossier du propriétaire.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.playlists_guard_client_fields() is
  'Verrouille item_count/owner_id/created_at à l''écriture côté client ; '
  'pose updated_at automatiquement ; impose que cover_path pointe dans le '
  'dossier de stockage du propriétaire (voir audit Phase 3.5).';

-- Le trigger existant pointe déjà vers cette fonction : `create or replace`
-- suffit, aucun trigger à recréer.

-- =============================================================================
-- 5) suggested_videos -- clips suggérés après lecture d'un clip publié.
--
--    SECURITY INVOKER (pas DEFINER) : la RLS de `videos` (videos_select_published
--    et consorts) s'applique donc naturellement à l'appelant, sans qu'on ait
--    besoin de dupliquer sa logique ici. Filtre explicite `status = 'published'`
--    conservé quand même (défense en profondeur, et garantit le contrat même
--    si les politiques RLS changeaient un jour pour un rôle plus permissif).
--    Colonnes de retour : EXACTEMENT celles de `videos` (moins la logique de
--    score) + `artist` en jsonb, alignées sur la forme consommée par
--    Video.fromJson (lib/features/video/domain/video.dart) via
--    SearchRepository._selectWithArtist (lib/features/search/data/search_repository.dart) :
--    `artist: { id, username, display_name, avatar_url, role, subscriber_count }`.
-- =============================================================================
create or replace function public.suggested_videos(
  p_video_id uuid,
  p_limit    int default 20
)
returns table (
  id                uuid,
  artist_id         uuid,
  title             text,
  description       text,
  genre_id          integer,
  video_path        text,
  thumbnail_path    text,
  duration_seconds  integer,
  size_bytes        bigint,
  status            public.video_status,
  moderation_result jsonb,
  view_count        bigint,
  like_count        bigint,
  comment_count     bigint,
  published_at      timestamptz,
  created_at        timestamptz,
  artist            jsonb
)
language sql
security invoker
set search_path = ''
stable
as $$
  with current_video as (
    select v.artist_id as cur_artist_id, v.genre_id as cur_genre_id
      from public.videos v
     where v.id = p_video_id
       and v.status = 'published'
  ),
  scored as (
    select
      v.*,
      -- Même artiste : poids fort. Même genre : poids moyen. Popularité
      -- (échelle logarithmique pour éviter qu'un seul clip très vu écrase
      -- tout le reste). Fraîcheur : léger malus par jour d'ancienneté.
      (case when v.artist_id = cv.cur_artist_id then 5.0 else 0.0 end)
      + (case when cv.cur_genre_id is not null and v.genre_id = cv.cur_genre_id then 2.0 else 0.0 end)
      + (ln(1 + v.view_count) * 0.3)
      + (ln(1 + v.like_count) * 0.5)
      - (extract(epoch from (now() - coalesce(v.published_at, v.created_at))) / 86400.0 * 0.02)
      as score
    from public.videos v
    cross join current_video cv
   where v.status = 'published'
     and v.id <> p_video_id
  )
  select
    s.id, s.artist_id, s.title, s.description, s.genre_id, s.video_path,
    s.thumbnail_path, s.duration_seconds, s.size_bytes, s.status,
    s.moderation_result, s.view_count, s.like_count, s.comment_count,
    s.published_at, s.created_at,
    jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'display_name', p.display_name,
      'avatar_url', p.avatar_url,
      'role', p.role,
      'subscriber_count', p.subscriber_count
    ) as artist
  from scored s
  join public.profiles p on p.id = s.artist_id
  order by s.score desc, s.published_at desc nulls last
  limit greatest(p_limit, 0)
$$;

comment on function public.suggested_videos(uuid, int) is
  'Clips publiés suggérés après p_video_id (jamais autre statut), classés par '
  'score explicite (même artiste, même genre, popularité, fraîcheur). '
  'SECURITY INVOKER : la RLS de videos/profiles s''applique à l''appelant.';

-- Fonction de lecture publique (le fil "à suivre" doit fonctionner pour un
-- visiteur non connecté, comme le fil "Nouveautés") : révocation du rôle
-- `public` trop permissif, puis ré-accord ciblé anon + authenticated.
revoke execute on function public.suggested_videos(uuid, int) from public;
grant execute on function public.suggested_videos(uuid, int) to anon, authenticated;
