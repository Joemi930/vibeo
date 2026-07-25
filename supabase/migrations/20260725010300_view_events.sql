-- Migration : table view_events + RPC record_view (anti-spam) + trigger de
-- compteur. Alimente le compteur `videos.view_count` et servira d'historique
-- de lecture (Phase 3) et de source pour les tendances (Phase 5).

-- ---------------------------------------------------------------------------
-- Table view_events.
-- ---------------------------------------------------------------------------
create table public.view_events (
  id              bigint generated always as identity primary key,
  video_id        uuid not null references public.videos (id) on delete cascade,
  user_id         uuid references public.profiles (id) on delete set null,
  session_key     text,
  watched_seconds integer not null check (watched_seconds >= 0),
  created_at      timestamptz not null default now(),

  -- Un événement de vue est rattaché à un utilisateur connecté OU à une clé
  -- de session opaque générée côté client pour dédupliquer les invités.
  check (user_id is not null or session_key is not null)
);

comment on table public.view_events is
  'Événements de lecture (vues), source du compteur videos.view_count et de '
  'l''historique de lecture (Phase 3) / des tendances (Phase 5). Écriture '
  'exclusivement via la RPC public.record_view (aucune politique insert).';

-- ---------------------------------------------------------------------------
-- Index sur les colonnes de filtre fréquent.
-- ---------------------------------------------------------------------------
create index view_events_video_created_idx
  on public.view_events (video_id, created_at desc);

-- Sert d'historique de lecture en Phase 3 (pas de table dédiée).
create index view_events_user_created_idx
  on public.view_events (user_id, created_at desc);

-- Anti-spam pour les invités (dédup par clé de session).
create index view_events_session_video_created_idx
  on public.view_events (session_key, video_id, created_at desc);

-- ---------------------------------------------------------------------------
-- RPC record_view : seul chemin d'écriture autorisé côté client.
-- SECURITY DEFINER : la fonction s'exécute avec les privilèges de son
-- propriétaire (postgres, qui contourne la RLS), ce qui permet l'insertion
-- même si aucune politique RLS ne l'autorise -- exactement comme
-- `handle_new_user` en Phase 1.
-- ---------------------------------------------------------------------------
create or replace function public.record_view(
  p_video_id uuid,
  p_watched_seconds integer,
  p_session_key text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id     uuid := auth.uid();
  v_status      public.video_status;
  v_duplicate   boolean;
begin
  -- 1) Une vue n'est comptée qu'après 10 s de lecture effective.
  if p_watched_seconds < 10 then
    return false;
  end if;

  -- 2) La vidéo doit exister et être publiée.
  select status into v_status
    from public.videos
   where id = p_video_id;

  if v_status is null or v_status <> 'published' then
    return false;
  end if;

  -- Il faut pouvoir identifier l'auteur de la vue (utilisateur connecté ou
  -- clé de session pour un invité), sinon l'anti-spam est impossible.
  if v_user_id is null and p_session_key is null then
    return false;
  end if;

  -- 3) Anti-spam : pas plus d'une vue comptée par (vidéo, auteur) toutes les
  -- 30 minutes glissantes.
  select exists (
    select 1
      from public.view_events
     where video_id = p_video_id
       and created_at >= now() - interval '30 minutes'
       and (
         (v_user_id is not null and user_id = v_user_id)
         or (v_user_id is null and session_key = p_session_key)
       )
  ) into v_duplicate;

  if v_duplicate then
    return false;
  end if;

  -- 4) Enregistrement de la vue (déclenche le trigger de compteur ci-dessous).
  insert into public.view_events (video_id, user_id, session_key, watched_seconds)
  values (p_video_id, v_user_id, p_session_key, p_watched_seconds);

  return true;
end;
$$;

comment on function public.record_view(uuid, integer, text) is
  'Enregistre une vue si >= 10s de lecture, vidéo publiée, et pas de doublon '
  'sur les 30 dernières minutes. Seul chemin d''écriture pour view_events.';

grant execute on function public.record_view(uuid, integer, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Trigger de compteur : view_count n'est JAMAIS modifié par le client
-- (règle CLAUDE.md n°6), uniquement par ce trigger.
-- ---------------------------------------------------------------------------
create or replace function public.view_events_increment_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.videos
     set view_count = view_count + 1
   where id = new.video_id;

  return new;
end;
$$;

create trigger view_events_increment_count_trigger
  after insert on public.view_events
  for each row
  execute function public.view_events_increment_count();

-- Fonction trigger : non appelable via /rpc par anon/authenticated.
revoke execute on function public.view_events_increment_count() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS. Aucune politique INSERT côté client : le seul chemin d'écriture est
-- la RPC `record_view` (SECURITY DEFINER, contourne la RLS comme
-- `handle_new_user`).
-- ---------------------------------------------------------------------------
alter table public.view_events enable row level security;

create policy view_events_select_own
  on public.view_events
  for select
  to authenticated
  using (user_id = auth.uid());

create policy view_events_select_admin
  on public.view_events
  for select
  to authenticated
  using (public.is_admin());

-- Lecture réservée à authenticated (pas d'usage anon direct sur cette table ;
-- les invités passent uniquement par la RPC record_view, sans lecture).
grant select on public.view_events to authenticated;
