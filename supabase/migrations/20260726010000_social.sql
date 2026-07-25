-- Migration : interactions sociales (Phase 3).
-- Tables : likes, comments, subscriptions, playlists, playlist_items, reports.
-- RLS activée dès la création de chaque table, politiques nommées, compteurs
-- exclusivement maintenus par triggers (règle CLAUDE.md n°6), rate limiting
-- sur les commentaires (30/h) et les signalements (20/j) (règle n°8).
-- Référence : docs/ARCHITECTURE.md §3 (schéma cible) et §4 (identité).

-- =============================================================================
-- 0) videos.comment_count -- nouvelle colonne compteur, alimentée par un
--    trigger sur `comments` (créée plus bas). Comme view_count/like_count,
--    elle doit être verrouillée côté client par `videos_guard_client_fields`.
--
--    MODIFICATION D'UNE FONCTION EXISTANTE (Phase 2) : on étend
--    `videos_guard_client_fields()` pour figer aussi `comment_count`, exactement
--    comme elle fige déjà `view_count`/`like_count`. Le reste de la fonction
--    (transitions de statut, published_at) est repris à l'identique.
-- =============================================================================
alter table public.videos
  add column comment_count bigint not null default 0;

comment on column public.videos.comment_count is
  'Nombre de commentaires actifs (non supprimés) sur le clip. Maintenu par '
  'trigger sur public.comments, jamais par le client.';

create or replace function public.videos_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Les compteurs démarrent toujours à zéro, jamais fournis par le client.
    new.view_count := 0;
    new.like_count := 0;
    new.comment_count := 0;

    -- À la création, seuls les statuts "neutres" sont autorisés : la vidéo
    -- vient d'être uploadée (processing) ou l'artiste la publie directement
    -- (published -- pas de file de modération avant la Phase 4). Les statuts
    -- de décision de modération ne peuvent pas être choisis à l'insertion.
    if new.status not in ('processing', 'published') then
      raise exception
        'Statut % non autorisé à la création d''une vidéo.', new.status
        using errcode = '42501';
    end if;

    -- Une vidéo créée directement en `published` doit porter son horodatage :
    -- sans lui elle serait absente du tri du fil "Nouveautés" (published_at
    -- NULL), alors même qu'elle est visible par la RLS.
    if new.status = 'published' then
      new.published_at := now();
    else
      new.published_at := null;
    end if;

    return new;
  end if;

  -- UPDATE côté client : les compteurs sont restaurés à leur valeur
  -- précédente, quoi que le client ait envoyé (défense en profondeur, même
  -- si aucune politique RLS n'accorde de UPDATE sur ces colonnes séparément).
  new.view_count := old.view_count;
  new.like_count := old.like_count;
  new.comment_count := old.comment_count;

  -- Interdiction de passer à un statut de décision de modération : ces
  -- transitions sont réservées à l'IA/l'admin (service_role), exemptés
  -- au-dessus.
  if new.status is distinct from old.status
     and new.status in ('pending_moderation', 'rejected', 'removed') then
    raise exception
      'Transition vers le statut % réservée à la modération.', new.status
      using errcode = '42501';
  end if;

  -- Horodatage de publication : posé automatiquement au premier passage en
  -- `published`, jamais fourni par le client (nécessaire au tri du fil
  -- "Nouveautés" sur `published_at`).
  if new.status = 'published' and old.status is distinct from 'published' then
    new.published_at := now();
  end if;

  return new;
end;
$$;

comment on function public.videos_guard_client_fields() is
  'Empêche le client de fixer les compteurs (dont comment_count depuis la '
  'Phase 3) ou de s''auto-décider un statut de modération.';

-- NOTE : pourquoi les triggers de compteur SECURITY DEFINER créés plus bas
-- (likes_maintain_video_like_count, comments_maintain_video_comment_count,
-- subscriptions_maintain_subscriber_count, playlist_items_maintain_item_count)
-- ne sont PAS bloqués par ce garde-fou (ni par `prevent_role_escalation` sur
-- `profiles`), sans qu'on ait besoin de les modifier :
-- une fonction SECURITY DEFINER s'exécute avec les privilèges de son
-- PROPRIÉTAIRE (ici `postgres`, qui a créé toutes ces migrations) ; `current_user`
-- vaut donc `postgres` pendant toute son exécution, y compris pour les
-- instructions UPDATE qu'elle émet et les triggers BEFORE qu'elles déclenchent
-- en cascade. Les gardes-fous exemptent déjà explicitement
-- `current_user in ('service_role', 'postgres', 'supabase_admin')` : ils
-- laissent donc passer nos triggers de compteur sans modification, exactement
-- comme `view_events_increment_count()` le fait déjà avec `view_count` depuis
-- la Phase 2.

-- =============================================================================
-- 1) likes -- clé composite (video_id, user_id) : l'unicité empêche le double
--    like. Pas de colonne id, pas de politique UPDATE (un like se supprime et
--    se recrée, il ne se "modifie" pas).
-- =============================================================================
create table public.likes (
  video_id   uuid not null references public.videos (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_id, user_id)
);

comment on table public.likes is
  'Likes sur les clips. Clé composite (video_id, user_id) : un like par '
  'utilisateur et par clip, la contrainte de PK empêche le double like.';

-- "Mes likes" (bibliothèque / historique de likes), plus récents d'abord.
create index likes_user_created_idx
  on public.likes (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Trigger de compteur : videos.like_count, jamais modifié par le client.
-- ---------------------------------------------------------------------------
create or replace function public.likes_maintain_video_like_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.videos
       set like_count = like_count + 1
     where id = new.video_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.videos
       set like_count = like_count - 1
     where id = old.video_id;
    return old;
  end if;
  return null;
end;
$$;

comment on function public.likes_maintain_video_like_count() is
  'Maintient videos.like_count en phase avec les lignes de public.likes.';

create trigger likes_maintain_video_like_count_trigger
  after insert or delete on public.likes
  for each row
  execute function public.likes_maintain_video_like_count();

revoke execute on function public.likes_maintain_video_like_count() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS.
-- ---------------------------------------------------------------------------
alter table public.likes enable row level security;

-- Le graphe social (qui a liké quoi) n'a pas besoin d'être public : les
-- totaux affichés viennent de videos.like_count (déjà public), et l'état
-- "isLiked" côté client ne lit que SES propres lignes. On restreint donc la
-- lecture à l'utilisateur concerné -- pas d'accès anon, pas de lecture des
-- likes d'un tiers par un utilisateur authentifié (audit sécurité Phase 3).
create policy likes_select_own
  on public.likes
  for select
  to authenticated
  using (user_id = auth.uid());

create policy likes_insert_own
  on public.likes
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy likes_delete_own
  on public.likes
  for delete
  to authenticated
  using (user_id = auth.uid());

-- Pas de politique UPDATE : un like ne se modifie pas (delete + insert).

grant select, insert, delete on public.likes to authenticated;

-- =============================================================================
-- 2) comments -- soft delete (deleted_at) pour préserver l'historique du fil
--    sans casser comment_count. L'auteur peut éditer/supprimer SES
--    commentaires ; un admin peut supprimer n'importe quel commentaire.
--    L'ARTISTE PROPRIÉTAIRE DU CLIP N'A AUCUN DROIT PARTICULIER ICI (critère
--    explicite du cahier des charges).
-- =============================================================================
create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  video_id   uuid not null references public.videos (id) on delete cascade,
  author_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table public.comments is
  'Commentaires sur les clips. Soft delete via deleted_at (préserve '
  'comment_count et le fil) ; author_id/video_id/created_at verrouillés par '
  'trigger. La suppression PHYSIQUE (DELETE) est réservée à l''auteur ou un admin.';

-- Pagination du fil de commentaires d'un clip, plus récents d'abord.
create index comments_video_created_idx
  on public.comments (video_id, created_at desc);

-- "Mes commentaires" + support de la limite de débit (30/h/utilisateur).
create index comments_author_created_idx
  on public.comments (author_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Garde-fou : author_id, video_id, created_at immuables côté client ; deleted_at
-- ignoré à la création ; updated_at posé automatiquement à chaque UPDATE.
-- Même structure que `videos_guard_client_fields` (rôles d'administration
-- exemptés). PAS SECURITY DEFINER : s'exécute sous l'identité de l'appelant
-- réel (authenticated), la RLS reste donc pleinement appliquée en parallèle.
-- ---------------------------------------------------------------------------
create or replace function public.comments_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.updated_at := now();
    new.deleted_at := null;
    return new;
  end if;

  -- UPDATE côté client : author_id, video_id, created_at sont immuables ;
  -- updated_at est posé automatiquement (ni figé à l'ancienne valeur, ni
  -- laissé au choix du client).
  new.author_id := old.author_id;
  new.video_id := old.video_id;
  new.created_at := old.created_at;
  new.updated_at := now();

  return new;
end;
$$;

comment on function public.comments_guard_client_fields() is
  'Verrouille author_id/video_id/created_at à l''écriture côté client ; pose '
  'updated_at automatiquement.';

create trigger comments_guard_client_fields_trigger
  before insert or update on public.comments
  for each row
  execute function public.comments_guard_client_fields();

-- ---------------------------------------------------------------------------
-- Rate limiting : 30 commentaires par heure glissante par utilisateur (règle
-- CLAUDE.md n°8). SECURITY DEFINER pour compter tous les commentaires de
-- l'auteur indépendamment de ce que la RLS laisserait voir à l'appelant.
--
-- ATTENTION (piège déjà rencontré en Phase 2) : dans une fonction SECURITY
-- DEFINER, `current_user` vaut le PROPRIÉTAIRE de la fonction (postgres), pas
-- l'appelant -- tester `current_user` ici exempterait tout le monde et
-- désactiverait silencieusement la limite. On identifie l'appelant réel par le
-- rôle porté par son JWT via `auth.role()` : `authenticated` = appel client
-- (quota appliqué), tout le reste (migration, cron, psql, service_role) = exempté.
-- ---------------------------------------------------------------------------
create or replace function public.comments_enforce_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent_count integer;
begin
  if auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  select count(*)
    into recent_count
    from public.comments
   where author_id = new.author_id
     and created_at >= now() - interval '1 hour';

  if recent_count >= 30 then
    raise exception
      'Limite de 30 commentaires par heure atteinte. Réessaie plus tard.'
      using errcode = '54000';
  end if;

  return new;
end;
$$;

comment on function public.comments_enforce_rate_limit() is
  'Bloque le 31e commentaire du même auteur sur 1h glissante.';

create trigger comments_enforce_rate_limit_trigger
  before insert on public.comments
  for each row
  execute function public.comments_enforce_rate_limit();

-- ---------------------------------------------------------------------------
-- Trigger de compteur : videos.comment_count.
--   INSERT                              -> +1
--   UPDATE deleted_at NULL -> NOT NULL   -> -1 (soft delete)
--   UPDATE deleted_at NOT NULL -> NULL   -> +1 (restauration admin directe)
--   DELETE physique, si non déjà supprimé -> -1
-- ---------------------------------------------------------------------------
create or replace function public.comments_maintain_video_comment_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.videos
       set comment_count = comment_count + 1
     where id = new.video_id;
    return new;
  elsif tg_op = 'UPDATE' then
    if old.deleted_at is null and new.deleted_at is not null then
      update public.videos
         set comment_count = comment_count - 1
       where id = new.video_id;
    elsif old.deleted_at is not null and new.deleted_at is null then
      update public.videos
         set comment_count = comment_count + 1
       where id = new.video_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.deleted_at is null then
      update public.videos
         set comment_count = comment_count - 1
       where id = old.video_id;
    end if;
    return old;
  end if;
  return null;
end;
$$;

comment on function public.comments_maintain_video_comment_count() is
  'Maintient videos.comment_count en fonction des insertions, soft/hard '
  'deletes de public.comments.';

create trigger comments_maintain_video_comment_count_trigger
  after insert or update or delete on public.comments
  for each row
  execute function public.comments_maintain_video_comment_count();

revoke execute on function public.comments_guard_client_fields() from public, anon, authenticated;
revoke execute on function public.comments_enforce_rate_limit() from public, anon, authenticated;
revoke execute on function public.comments_maintain_video_comment_count() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS.
-- ---------------------------------------------------------------------------
alter table public.comments enable row level security;

-- Lecture publique des commentaires non supprimés.
create policy comments_select_public
  on public.comments
  for select
  to anon, authenticated
  using (deleted_at is null);

-- Un admin voit aussi les commentaires supprimés (modération/audit).
create policy comments_select_admin
  on public.comments
  for select
  to authenticated
  using (public.is_admin());

-- On ne peut commenter qu'en son nom, et seulement un clip publié.
create policy comments_insert_own_on_published_video
  on public.comments
  for insert
  to authenticated
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.videos v
       where v.id = video_id
         and v.status = 'published'
    )
  );

-- Édition du corps (et soft delete via deleted_at) : réservée à l'auteur.
create policy comments_update_own
  on public.comments
  for update
  to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

-- Suppression PHYSIQUE : l'auteur ou un admin. Explicitement PAS l'artiste
-- propriétaire du clip commenté (critère du cahier des charges).
create policy comments_delete_own
  on public.comments
  for delete
  to authenticated
  using (author_id = auth.uid());

create policy comments_delete_admin
  on public.comments
  for delete
  to authenticated
  using (public.is_admin());

grant select on public.comments to anon;
grant select, insert, update, delete on public.comments to authenticated;

-- =============================================================================
-- 3) subscriptions -- abonnement d'un auditeur/artiste (subscriber) à un
--    artiste (artist). Maintient profiles.subscriber_count (colonne créée en
--    Phase 3 anticipée par 20260725010000_profiles_public_read.sql).
-- =============================================================================
create table public.subscriptions (
  artist_id     uuid not null references public.profiles (id) on delete cascade,
  subscriber_id uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (artist_id, subscriber_id),
  check (artist_id <> subscriber_id)
);

comment on table public.subscriptions is
  'Abonnements aux artistes. On ne peut pas s''abonner à soi-même '
  '(check artist_id <> subscriber_id).';

-- "Mes abonnements" (bibliothèque), plus récents d'abord.
create index subscriptions_subscriber_created_idx
  on public.subscriptions (subscriber_id, created_at desc);

-- Compte des abonnés d'un artiste (déjà couvert par la PK, mais utile pour
-- des requêtes qui filtrent uniquement sur artist_id sans subscriber_id).
create index subscriptions_artist_idx
  on public.subscriptions (artist_id);

-- ---------------------------------------------------------------------------
-- Trigger de compteur : profiles.subscriber_count. Aucune modification de
-- `prevent_role_escalation()` nécessaire -- voir la note générale en tête de
-- fichier : SECURITY DEFINER => current_user = postgres => exemption déjà en
-- place au sommet de cette fonction.
-- ---------------------------------------------------------------------------
create or replace function public.subscriptions_maintain_subscriber_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles
       set subscriber_count = subscriber_count + 1
     where id = new.artist_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.profiles
       set subscriber_count = subscriber_count - 1
     where id = old.artist_id;
    return old;
  end if;
  return null;
end;
$$;

comment on function public.subscriptions_maintain_subscriber_count() is
  'Maintient profiles.subscriber_count en phase avec public.subscriptions.';

create trigger subscriptions_maintain_subscriber_count_trigger
  after insert or delete on public.subscriptions
  for each row
  execute function public.subscriptions_maintain_subscriber_count();

revoke execute on function public.subscriptions_maintain_subscriber_count() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS.
-- ---------------------------------------------------------------------------
alter table public.subscriptions enable row level security;

-- Même raisonnement que pour `likes` : qui suit quel artiste n'a pas besoin
-- d'être public. profiles.subscriber_count (déjà public) suffit à afficher
-- les totaux ; "isSubscribed" et la liste "mes abonnements" ne lisent que
-- SES propres lignes. Lecture restreinte au seul abonné concerné.
create policy subscriptions_select_own
  on public.subscriptions
  for select
  to authenticated
  using (subscriber_id = auth.uid());

create policy subscriptions_insert_own
  on public.subscriptions
  for insert
  to authenticated
  with check (subscriber_id = auth.uid());

create policy subscriptions_delete_own
  on public.subscriptions
  for delete
  to authenticated
  using (subscriber_id = auth.uid());

grant select, insert, delete on public.subscriptions to authenticated;

-- =============================================================================
-- 4) playlists -- privées par défaut. item_count maintenu par trigger sur
--    playlist_items (créée juste après).
-- =============================================================================
create table public.playlists (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 80),
  description text check (char_length(description) <= 500),
  is_public   boolean not null default false,
  item_count  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.playlists is
  'Playlists créées par les utilisateurs. Privées par défaut (is_public = '
  'false). item_count maintenu par trigger sur public.playlist_items.';

-- "Mes playlists" (bibliothèque), plus récentes d'abord.
create index playlists_owner_created_idx
  on public.playlists (owner_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Garde-fou : item_count verrouillé côté client, owner_id immuable à
-- l'UPDATE, updated_at posé automatiquement. Même structure que
-- `comments_guard_client_fields`.
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
    return new;
  end if;

  new.item_count := old.item_count;
  new.owner_id := old.owner_id;
  new.created_at := old.created_at;
  new.updated_at := now();

  return new;
end;
$$;

comment on function public.playlists_guard_client_fields() is
  'Verrouille item_count/owner_id/created_at à l''écriture côté client ; '
  'pose updated_at automatiquement.';

create trigger playlists_guard_client_fields_trigger
  before insert or update on public.playlists
  for each row
  execute function public.playlists_guard_client_fields();

revoke execute on function public.playlists_guard_client_fields() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS.
-- ---------------------------------------------------------------------------
alter table public.playlists enable row level security;

-- Visible par son propriétaire, ou par tout le monde si publique.
create policy playlists_select_visible
  on public.playlists
  for select
  to anon, authenticated
  using (is_public or owner_id = auth.uid());

create policy playlists_insert_own
  on public.playlists
  for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy playlists_update_own
  on public.playlists
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy playlists_delete_own
  on public.playlists
  for delete
  to authenticated
  using (owner_id = auth.uid());

grant select on public.playlists to anon;
grant select, insert, update, delete on public.playlists to authenticated;

-- =============================================================================
-- 5) playlist_items -- clé composite (playlist_id, video_id) : pas deux fois
--    le même clip dans une playlist.
--
--    Choix sur `position` : PAS d'index UNIQUE sur (playlist_id, position).
--    Un index unique "immédiat" (non DEFERRABLE) empêcherait tout
--    réordonnancement par swap : Postgres valide l'unicité ligne par ligne au
--    fil d'un UPDATE, donc même un UPDATE en masse dans une seule instruction
--    peut heurter un état intermédiaire en collision. Le rendre DEFERRABLE
--    INITIALLY DEFERRED aurait marché, mais aurait ajouté une contrainte
--    supplémentaire à maintenir sans bénéfice réel : la RPC
--    `reorder_playlist` ci-dessous est le SEUL chemin de réordonnancement en
--    masse, elle réécrit TOUTES les positions en une transaction et
--    normalise donc l'ordre à chaque appel. On se contente d'un index simple
--    (non unique) pour accélérer le tri `order by position`, avec `added_at`
--    comme critère de tri secondaire stable en cas de doublon accidentel de
--    position (ex. écriture directe hors RPC).
-- =============================================================================
create table public.playlist_items (
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  video_id    uuid not null references public.videos (id) on delete cascade,
  position    integer not null,
  added_at    timestamptz not null default now(),
  primary key (playlist_id, video_id)
);

comment on table public.playlist_items is
  'Clips d''une playlist. PK (playlist_id, video_id) : un clip ne peut '
  'apparaître qu''une fois par playlist. position non contrainte UNIQUE '
  '(voir commentaire ci-dessus) : ordre normalisé par la RPC reorder_playlist.';

create index playlist_items_playlist_position_idx
  on public.playlist_items (playlist_id, position, added_at);

-- ---------------------------------------------------------------------------
-- Trigger de compteur : playlists.item_count.
-- ---------------------------------------------------------------------------
create or replace function public.playlist_items_maintain_item_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.playlists
       set item_count = item_count + 1
     where id = new.playlist_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.playlists
       set item_count = item_count - 1
     where id = old.playlist_id;
    return old;
  end if;
  return null;
end;
$$;

comment on function public.playlist_items_maintain_item_count() is
  'Maintient playlists.item_count en phase avec public.playlist_items.';

create trigger playlist_items_maintain_item_count_trigger
  after insert or delete on public.playlist_items
  for each row
  execute function public.playlist_items_maintain_item_count();

revoke execute on function public.playlist_items_maintain_item_count() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS -- dérivée de la playlist parente.
-- ---------------------------------------------------------------------------
alter table public.playlist_items enable row level security;

create policy playlist_items_select_visible
  on public.playlist_items
  for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.playlists p
       where p.id = playlist_id
         and (p.is_public or p.owner_id = auth.uid())
    )
  );

create policy playlist_items_insert_own
  on public.playlist_items
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.playlists p
       where p.id = playlist_id
         and p.owner_id = auth.uid()
    )
  );

create policy playlist_items_update_own
  on public.playlist_items
  for update
  to authenticated
  using (
    exists (
      select 1 from public.playlists p
       where p.id = playlist_id
         and p.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.playlists p
       where p.id = playlist_id
         and p.owner_id = auth.uid()
    )
  );

create policy playlist_items_delete_own
  on public.playlist_items
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.playlists p
       where p.id = playlist_id
         and p.owner_id = auth.uid()
    )
  );

grant select on public.playlist_items to anon;
grant select, insert, update, delete on public.playlist_items to authenticated;

-- ---------------------------------------------------------------------------
-- RPC reorder_playlist : réécrit les positions en une seule transaction.
-- SECURITY DEFINER (contourne la RLS pour la mise à jour en masse) mais
-- vérifie elle-même la propriété -- ne PAS supprimer cette vérification, elle
-- remplace la RLS le temps de l'exécution.
-- ---------------------------------------------------------------------------
create or replace function public.reorder_playlist(
  p_playlist_id uuid,
  p_video_ids   uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id       uuid;
  v_expected_count integer;
  v_provided_count integer;
  v_updated_count  integer;
begin
  select owner_id
    into v_owner_id
    from public.playlists
   where id = p_playlist_id;

  if v_owner_id is null then
    raise exception 'Playlist introuvable.' using errcode = 'P0002';
  end if;

  if v_owner_id <> auth.uid() then
    raise exception 'Seul le propriétaire peut réordonner cette playlist.'
      using errcode = '42501';
  end if;

  if p_video_ids is null or array_length(p_video_ids, 1) is null then
    raise exception 'Liste de clips vide.' using errcode = '22023';
  end if;

  select count(*)
    into v_expected_count
    from public.playlist_items
   where playlist_id = p_playlist_id;

  select count(distinct v)
    into v_provided_count
    from unnest(p_video_ids) as v;

  -- Le tableau fourni doit couvrir EXACTEMENT les clips existants de la
  -- playlist, sans doublon ni ajout/suppression implicite : ce n'est pas la
  -- RPC qui gère l'ajout/retrait de clips (playlist_items_insert_own /
  -- _delete_own s'en chargent), seulement leur ordre.
  if v_provided_count <> array_length(p_video_ids, 1)
     or v_provided_count <> v_expected_count then
    raise exception
      'La liste fournie doit contenir exactement les % clip(s) de la playlist, sans doublon.',
      v_expected_count
      using errcode = '22023';
  end if;

  update public.playlist_items pi
     set position = t.ord - 1
    from unnest(p_video_ids) with ordinality as t (video_id, ord)
   where pi.playlist_id = p_playlist_id
     and pi.video_id = t.video_id;

  get diagnostics v_updated_count = row_count;

  if v_updated_count <> v_expected_count then
    raise exception
      'Un ou plusieurs clips fournis n''appartiennent pas à cette playlist.'
      using errcode = '22023';
  end if;
end;
$$;

comment on function public.reorder_playlist(uuid, uuid[]) is
  'Réécrit les positions des clips d''une playlist selon l''ordre du tableau '
  'fourni, en une transaction. Vérifie la propriété (owner_id = auth.uid()) '
  'et que le tableau couvre exactement les clips existants.';

revoke execute on function public.reorder_playlist(uuid, uuid[]) from public, anon;
grant execute on function public.reorder_playlist(uuid, uuid[]) to authenticated;

-- =============================================================================
-- 6) reports -- signalement d'un clip OU d'un commentaire (exactement une
--    cible). Lecture strictement réservée aux admins : un utilisateur ne doit
--    PAS pouvoir relire ses propres signalements ni ceux des autres.
-- =============================================================================
create type public.report_reason as enum (
  'spam',
  'hate_speech',
  'sexual_content',
  'violence',
  'copyright',
  'misinformation',
  'other'
);

create type public.report_status as enum (
  'pending',
  'reviewed',
  'dismissed'
);

-- Ce que visait le signalement, conservé même après suppression de la cible
-- (voir plus bas pourquoi video_id/comment_id passent en ON DELETE SET NULL).
create type public.report_target as enum ('video', 'comment');

create table public.reports (
  id                uuid primary key default gen_random_uuid(),
  reporter_id       uuid not null references public.profiles (id) on delete cascade,

  -- AUDIT SÉCURITÉ (correctif) : une cascade FK Postgres s'exécute HORS RLS.
  -- Avec `on delete cascade`, l'auteur d'un clip/commentaire signalé -- qui a
  -- le droit de supprimer SON PROPRE contenu via videos_delete_own /
  -- comments_delete_own -- effacerait du même coup, silencieusement, toutes
  -- les lignes `reports` qui le visaient, avant même qu'un admin les ait
  -- lues. `on delete set null` conserve la ligne de signalement ; `target_kind`
  -- et `target_author_id` (ci-dessous) préservent le contexte de modération
  -- même quand la cible n'existe plus.
  video_id          uuid references public.videos (id) on delete set null,
  comment_id        uuid references public.comments (id) on delete set null,

  -- Nature de la cible, figée à l'insertion (déduite par le trigger, jamais
  -- fournie par le client) : reste connue même si video_id/comment_id
  -- deviennent NULL suite à la suppression de la cible.
  target_kind       public.report_target not null,

  -- Auteur du contenu signalé, capturé à l'insertion en lisant
  -- videos.artist_id / comments.author_id (jamais depuis ce qu'envoie le
  -- client). Permet de repérer un récidiviste même s'il supprime ses
  -- contenus pour faire disparaître les signalements. Lisible par les admins
  -- uniquement, comme le reste de la table.
  target_author_id  uuid references public.profiles (id) on delete set null,

  reason            public.report_reason not null,
  details           text check (char_length(details) <= 1000),
  status            public.report_status not null default 'pending',
  created_at        timestamptz not null default now(),
  reviewed_at       timestamptz,
  -- Référence historique : si l'admin qui a traité le signalement est
  -- supprimé, on conserve le signalement (SET NULL, pas CASCADE).
  reviewed_by       uuid references public.profiles (id) on delete set null,

  -- Cohérence cible/nature : selon target_kind, l'AUTRE colonne de cible doit
  -- être nulle. L'identifiant de cible lui-même peut désormais être nul (cas
  -- d'une cible supprimée après coup) -- seule invariante forte à l'insertion
  -- (cf. reports_guard_client_fields, qui exige alors exactement une cible
  -- non nulle) : ici on ne garde que la cohérence structurelle, pas
  -- l'obligation de non-nullité.
  check (
    (target_kind = 'video' and comment_id is null)
    or (target_kind = 'comment' and video_id is null)
  )
);

comment on table public.reports is
  'Signalements de clips ou de commentaires. target_kind/target_author_id '
  'conservent le contexte de modération même après suppression de la cible '
  '(video_id/comment_id passent alors à NULL via ON DELETE SET NULL, en '
  'dehors de toute RLS). Lecture strictement réservée aux admins -- un '
  'utilisateur ne relit jamais ses propres signalements via l''API.';

-- File de modération admin : signalements en attente, plus anciens d'abord.
create index reports_status_created_idx
  on public.reports (status, created_at desc);

-- Support de la limite de débit (20/j/utilisateur).
create index reports_reporter_created_idx
  on public.reports (reporter_id, created_at desc);

-- Unicité : un même utilisateur ne signale pas deux fois la même cible.
--
-- Les index sont partiels (`where ... is not null`) : quand la cible est
-- supprimée, la colonne passe à NULL et la ligne sort de l'index. C'est
-- voulu -- l'unicité n'a plus d'objet une fois la cible disparue, et deux
-- signalements orphelins du même utilisateur ne gênent personne.
create unique index reports_reporter_video_unique_idx
  on public.reports (reporter_id, video_id)
  where video_id is not null;

create unique index reports_reporter_comment_unique_idx
  on public.reports (reporter_id, comment_id)
  where comment_id is not null;

-- Récidive : retrouver tous les signalements visant les contenus d'un auteur,
-- même après que celui-ci ait supprimé les contenus en question.
create index reports_target_author_idx
  on public.reports (target_author_id, created_at desc)
  where target_author_id is not null;

-- ---------------------------------------------------------------------------
-- Garde-fou : reporter_id/video_id/comment_id/created_at immuables ; status
-- et champs de décision forcés à leur valeur neutre à l'INSERT (le client ne
-- peut pas s'auto-déclarer un signalement déjà "reviewed").
-- ---------------------------------------------------------------------------
create or replace function public.reports_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.created_at := now();

    -- Exactement une cible : la contrainte CHECK de la table est volontairement
    -- plus souple (elle doit accepter l'état « cible supprimée »), c'est donc
    -- ici que l'invariant de création est tenu.
    if (new.video_id is null) = (new.comment_id is null) then
      raise exception
        'Un signalement vise un clip OU un commentaire, jamais les deux ni aucun.'
        using errcode = '22023';
    end if;

    -- `target_kind` et `target_author_id` ne sont jamais pris du client : ils
    -- sont déduits et lus en base. Ils survivent à la suppression de la cible
    -- et sont la seule trace permettant à la modération de repérer un
    -- récidiviste qui efface ses contenus.
    if new.video_id is not null then
      new.target_kind := 'video';
      select v.artist_id into new.target_author_id
        from public.videos v
       where v.id = new.video_id;
    else
      new.target_kind := 'comment';
      select c.author_id into new.target_author_id
        from public.comments c
       where c.id = new.comment_id;
    end if;

    -- Fonction INVOKER (surtout pas SECURITY DEFINER : `current_user` vaudrait
    -- alors `postgres` et l'exemption ci-dessus désactiverait tout ce garde-fou).
    -- Les deux SELECT passent donc par la RLS de l'appelant : si la cible ne
    -- lui est pas visible, il n'avait de toute façon pas à la signaler.
    if new.target_author_id is null then
      raise exception 'Cible de signalement introuvable.'
        using errcode = '22023';
    end if;

    return new;
  end if;

  -- UPDATE côté client : de toute façon réservé aux admins par la RLS
  -- (reports_update_admin), mais on verrouille la cible et l'auteur par
  -- défense en profondeur.
  new.reporter_id := old.reporter_id;
  new.video_id := old.video_id;
  new.comment_id := old.comment_id;
  new.target_kind := old.target_kind;
  new.target_author_id := old.target_author_id;
  new.created_at := old.created_at;

  return new;
end;
$$;

comment on function public.reports_guard_client_fields() is
  'Verrouille reporter_id/cible/created_at ; force status=pending et '
  'reviewed_*=null à la création ; déduit target_kind et target_author_id '
  'depuis la base pour conserver la trace de modération après suppression '
  'de la cible.';

create trigger reports_guard_client_fields_trigger
  before insert or update on public.reports
  for each row
  execute function public.reports_guard_client_fields();

-- ---------------------------------------------------------------------------
-- Rate limiting : 20 signalements par jour glissant par utilisateur. Même
-- piège que pour les commentaires : `auth.role()`, jamais `current_user`,
-- dans une fonction SECURITY DEFINER.
-- ---------------------------------------------------------------------------
create or replace function public.reports_enforce_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent_count integer;
begin
  if auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  select count(*)
    into recent_count
    from public.reports
   where reporter_id = new.reporter_id
     and created_at >= now() - interval '24 hours';

  if recent_count >= 20 then
    raise exception
      'Limite de 20 signalements par jour atteinte. Réessaie demain.'
      using errcode = '54000';
  end if;

  return new;
end;
$$;

comment on function public.reports_enforce_rate_limit() is
  'Bloque le 21e signalement du même utilisateur sur 24h glissantes.';

create trigger reports_enforce_rate_limit_trigger
  before insert on public.reports
  for each row
  execute function public.reports_enforce_rate_limit();

revoke execute on function public.reports_guard_client_fields() from public, anon, authenticated;
revoke execute on function public.reports_enforce_rate_limit() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS.
-- ---------------------------------------------------------------------------
alter table public.reports enable row level security;

create policy reports_insert_own
  on public.reports
  for insert
  to authenticated
  with check (reporter_id = auth.uid());

-- Lecture réservée aux admins -- AUCUNE politique select_own : un
-- utilisateur ne doit pas pouvoir relire ses propres signalements.
create policy reports_select_admin
  on public.reports
  for select
  to authenticated
  using (public.is_admin());

create policy reports_update_admin
  on public.reports
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Pas de politique DELETE : les signalements ne se suppriment pas côté client.

grant select, insert, update on public.reports to authenticated;

-- =============================================================================
-- 7) view_events -- historique de lecture pour la bibliothèque (Phase 3).
--
--    RIEN À FAIRE ICI : la migration 20260725010300_view_events.sql a déjà
--    créé, dans le même fichier que la table, les politiques
--    `view_events_select_own` (user_id = auth.uid()) et
--    `view_events_select_admin` (public.is_admin()), ainsi que le GRANT
--    SELECT à `authenticated`. Vérifié : `view_events_select_own` ne renvoie
--    que les lignes de l'appelant, aucune autre politique select n'ouvre
--    davantage l'accès (couvert par le test rls_social_test.sql, section 10).
-- =============================================================================

-- =============================================================================
-- 8) Recherche -- index trigram.
--
--    `videos.title` : déjà indexé par `videos_title_trgm_idx`
--    (20260725010100_videos.sql). `profiles.username` et
--    `profiles.display_name` : déjà indexés par `profiles_username_trgm_idx`
--    et `profiles_display_name_trgm_idx` (20260725010000_profiles_public_read.sql).
--    `pg_trgm` déjà activé par cette même migration. Aucun index à recréer.
-- =============================================================================
