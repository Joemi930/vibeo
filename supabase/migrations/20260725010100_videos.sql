-- Migration : table des vidéos (clips) + RLS + triggers de garde/quota.
-- Phase 2 (Vidéo). RLS activée dès la création, politiques nommées.
-- Référence : docs/ARCHITECTURE.md §3 (schéma cible) et §6 (sécurité).

-- ---------------------------------------------------------------------------
-- Enum des statuts de vidéo. `pending_moderation` n'est pas encore utilisé en
-- Phase 2 (pas de modération IA avant la Phase 4) mais est créé dès
-- maintenant pour éviter un `alter type` ultérieur (ajout de valeur d'enum
-- fragile en présence de transactions concurrentes).
-- ---------------------------------------------------------------------------
create type public.video_status as enum (
  'processing',
  'pending_moderation',
  'published',
  'rejected',
  'removed'
);

-- ---------------------------------------------------------------------------
-- Table videos.
-- ---------------------------------------------------------------------------
create table public.videos (
  id                uuid primary key default gen_random_uuid(),
  artist_id         uuid not null references public.profiles (id) on delete cascade,
  title             text not null check (char_length(title) between 1 and 120),
  description       text check (char_length(description) <= 5000),
  genre_id          integer references public.genres (id) on delete set null,
  video_path        text not null,
  thumbnail_path    text,
  duration_seconds  integer check (duration_seconds > 0 and duration_seconds <= 240),
  size_bytes        bigint check (size_bytes > 0 and size_bytes <= 62914560), -- 60 Mo (tier gratuit 1 Go)
  status            public.video_status not null default 'processing',
  moderation_result jsonb,
  view_count        bigint not null default 0,
  like_count        bigint not null default 0,
  published_at      timestamptz,
  created_at        timestamptz not null default now()
);

comment on table public.videos is
  'Clips vidéo publiés par les artistes. Compteurs (view_count, like_count) '
  'exclusivement mis à jour par triggers SQL, jamais par le client.';

-- ---------------------------------------------------------------------------
-- Index sur les colonnes de filtre fréquent.
-- ---------------------------------------------------------------------------
-- Fil "Nouveautés" : uniquement les vidéos publiées, triées par date de
-- publication. Index partiel : léger, ne couvre que les lignes utiles.
create index videos_published_feed_idx
  on public.videos (status, published_at desc)
  where status = 'published';

-- Studio artiste : liste des vidéos d'un artiste, plus récentes d'abord.
create index videos_artist_created_idx
  on public.videos (artist_id, created_at desc);

-- Filtre par genre.
create index videos_genre_idx
  on public.videos (genre_id);

-- Recherche floue sur le titre (Phase 3). pg_trgm déjà installé dans
-- `extensions` par la migration 20260725010000_profiles_public_read.sql.
create index videos_title_trgm_idx
  on public.videos
  using gin (title extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Garde-fou côté client : les compteurs et certaines transitions de statut
-- ne doivent JAMAIS être décidés par le client (règle CLAUDE.md n°6 et §4 de
-- l'architecture -- la modération/décision admin passe par service_role).
-- Même esprit que `prevent_role_escalation()` (Phase 1) : les rôles
-- d'administration de la base sont exemptés (service_role = Edge Functions /
-- cron, postgres = migrations/admin direct).
-- ---------------------------------------------------------------------------
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
  'Empêche le client de fixer les compteurs ou de s''auto-décider un statut de modération.';

create trigger videos_guard_client_fields_trigger
  before insert or update on public.videos
  for each row
  execute function public.videos_guard_client_fields();

-- ---------------------------------------------------------------------------
-- Rate limiting : 5 publications par artiste par 24 h glissantes (règle
-- CLAUDE.md n°8). SECURITY DEFINER pour compter TOUTES les vidéos de
-- l'artiste (y compris non `published`), indépendamment de ce que la RLS
-- laisserait voir à l'appelant.
--
-- ATTENTION : dans une fonction SECURITY DEFINER, `current_user` vaut le
-- PROPRIÉTAIRE de la fonction (postgres), pas l'appelant. Tester
-- `current_user in ('postgres', ...)` ici exempterait donc TOUT LE MONDE et
-- désactiverait silencieusement le quota. On identifie l'appelant réel par le
-- rôle porté par son JWT : `authenticated` = appel client (quota appliqué),
-- `service_role` ou absence de JWT (migration, cron, psql) = exempté.
-- ---------------------------------------------------------------------------
create or replace function public.videos_enforce_upload_rate_limit()
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
    from public.videos
   where artist_id = new.artist_id
     and created_at >= now() - interval '24 hours';

  if recent_count >= 5 then
    raise exception
      'Limite de 5 publications par jour atteinte. Réessaie demain.'
      using errcode = '54000';
  end if;

  return new;
end;
$$;

comment on function public.videos_enforce_upload_rate_limit() is
  'Bloque la création d''une 6e vidéo par le même artiste sur 24h glissantes.';

create trigger videos_enforce_upload_rate_limit_trigger
  before insert on public.videos
  for each row
  execute function public.videos_enforce_upload_rate_limit();

-- Fonctions trigger : non appelables via /rpc par anon/authenticated (elles
-- n'ont de sens que dans le contexte d'un trigger). Même pattern que
-- 20260724010300_harden_functions.sql.
revoke execute on function public.videos_guard_client_fields() from public, anon, authenticated;
revoke execute on function public.videos_enforce_upload_rate_limit() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS.
-- ---------------------------------------------------------------------------
alter table public.videos enable row level security;

-- Lecture publique des vidéos publiées (fil, page artiste, lecteur).
create policy videos_select_published
  on public.videos
  for select
  to anon, authenticated
  using (status = 'published');

-- Un artiste voit toutes SES vidéos, quel que soit leur statut (Studio).
create policy videos_select_own
  on public.videos
  for select
  to authenticated
  using (artist_id = auth.uid());

-- Un admin voit toutes les vidéos (file de modération à venir en Phase 4).
create policy videos_select_admin
  on public.videos
  for select
  to authenticated
  using (public.is_admin());

-- Seul un artiste vérifié peut créer une vidéo, et uniquement en son nom.
--
-- Les chemins de fichiers doivent en outre pointer vers le dossier storage de
-- l'artiste (premier segment = son auth.uid()). Sans cette vérification, un
-- artiste pourrait publier une fiche référençant le fichier ENCORE PRIVÉ d'un
-- autre artiste : la politique storage `videos_storage_select_published`
-- deviendrait alors vraie pour ce fichier et le rendrait lisible par tous.
create policy videos_insert_own_artist
  on public.videos
  for insert
  to authenticated
  with check (
    artist_id = auth.uid()
    and public.is_artist(auth.uid())
    and split_part(video_path, '/', 1) = auth.uid()::text
    and (
      thumbnail_path is null
      or split_part(thumbnail_path, '/', 1) = auth.uid()::text
    )
  );

-- Un artiste ne modifie que SES vidéos (titre, description, genre, statut
-- limité par le trigger ci-dessus). Même contrainte de propriété sur les
-- chemins, sinon la vérification ci-dessus se contournerait par un UPDATE.
create policy videos_update_own
  on public.videos
  for update
  to authenticated
  using (artist_id = auth.uid())
  with check (
    artist_id = auth.uid()
    and split_part(video_path, '/', 1) = auth.uid()::text
    and (
      thumbnail_path is null
      or split_part(thumbnail_path, '/', 1) = auth.uid()::text
    )
  );

-- Suppression : le propriétaire ou un admin.
create policy videos_delete_own
  on public.videos
  for delete
  to authenticated
  using (artist_id = auth.uid());

create policy videos_delete_admin
  on public.videos
  for delete
  to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Droits d'accès table. anon ne fait que lire (vidéos publiées, filtrées par
-- RLS) ; authenticated a en plus insert/update/delete (filtrés par RLS).
-- ---------------------------------------------------------------------------
grant select on public.videos to anon;
grant select, insert, update, delete on public.videos to authenticated;
