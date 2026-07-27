-- =========================================================================
-- Test RLS/fonctionnel — découverte (Phase 5) : trending_videos,
-- trending_videos_feed(), recommended_videos().
-- Démontre :
--   1. Une vidéo à 500 vues datant de 10 jours (hors fenêtre 7j) n'apparaît
--      PAS dans trending_videos_feed().
--   2. Une vidéo à 20 vues d'hier y apparaît.
--   3. TEST DÉCISIF DU MONTAGE : une vidéo présente en tendances, passée au
--      statut `removed` SANS rafraîchir la vue matérialisée, disparaît
--      IMMÉDIATEMENT de trending_videos_feed() -- preuve que la RLS/le
--      statut de videos se réapplique bien à la lecture.
--   4. Un compte qui n'a regardé que du hip-hop reçoit du hip-hop en tête de
--      recommended_videos(), même une vidéo jamais vue par lui (affinité de
--      genre), devant une vidéo pop plus "tendance" mais hors de son affinité.
--   5. Un compte neuf (aucun view_events) reçoit EXACTEMENT la même liste que
--      trending_videos_feed().
--   6. Un invité (anon) peut appeler les deux fonctions sans erreur.
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/discovery_test.sql
-- =========================================================================

begin;

-- ---------------------------------------------------------------------------
-- Comptes de test.
-- ---------------------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'f1000000-0000-0000-0000-00000000000f',
   'authenticated', 'authenticated', 'disc_artist@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"disc_artist"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'f2000000-0000-0000-0000-00000000000f',
   'authenticated', 'authenticated', 'disc_rapfan@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"disc_rapfan"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'f3000000-0000-0000-0000-00000000000f',
   'authenticated', 'authenticated', 'disc_newbie@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"disc_newbie"}'::jsonb);

update public.profiles set role = 'artist' where id = 'f1000000-0000-0000-0000-00000000000f';

reset role;

-- ---------------------------------------------------------------------------
-- Vidéos (insérées directement en tant que postgres, statut published
-- imposé -- même raccourci que les autres fichiers de test).
-- ---------------------------------------------------------------------------
-- V1 : ancienne, 500 vues -- mais TOUTES datées d'il y a 10 jours (hors
-- fenêtre glissante de 7 jours de trending_videos).
insert into public.videos
  (id, artist_id, title, genre_id, video_path, duration_seconds, size_bytes, status, published_at, created_at)
values (
  '10000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-00000000000f',
  'Vieux tube très vu il y a longtemps',
  (select id from public.genres where slug = 'pop'),
  'f1000000-0000-0000-0000-00000000000f/v1.mp4',
  60, 1000000, 'published', now() - interval '90 days', now() - interval '90 days'
);

-- V2 : récente, 20 vues d'hier (dans la fenêtre).
insert into public.videos
  (id, artist_id, title, genre_id, video_path, duration_seconds, size_bytes, status, published_at, created_at)
values (
  '10000000-0000-0000-0000-000000000002',
  'f1000000-0000-0000-0000-00000000000f',
  'Clip récent modeste',
  (select id from public.genres where slug = 'hip-hop'),
  'f1000000-0000-0000-0000-00000000000f/v2.mp4',
  60, 1000000, 'published', now() - interval '1 day', now() - interval '1 day'
);

-- V3 : va servir au test décisif -- en tendances, puis retirée sans refresh.
insert into public.videos
  (id, artist_id, title, genre_id, video_path, duration_seconds, size_bytes, status, published_at, created_at)
values (
  '10000000-0000-0000-0000-000000000003',
  'f1000000-0000-0000-0000-00000000000f',
  'Clip qui va être retiré',
  (select id from public.genres where slug = 'pop'),
  'f1000000-0000-0000-0000-00000000000f/v3.mp4',
  60, 1000000, 'published', now() - interval '2 days', now() - interval '2 days'
);

-- V4, V5 : hip-hop, peu/pas de vues récentes -- serviront à construire
-- l'affinité de genre du fan de rap (il les a regardées).
insert into public.videos
  (id, artist_id, title, genre_id, video_path, duration_seconds, size_bytes, status, published_at, created_at)
values
  ('10000000-0000-0000-0000-000000000004', 'f1000000-0000-0000-0000-00000000000f',
   'Rap watched 1', (select id from public.genres where slug = 'hip-hop'),
   'f1000000-0000-0000-0000-00000000000f/v4.mp4', 60, 1000000, 'published',
   now() - interval '20 days', now() - interval '20 days'),
  ('10000000-0000-0000-0000-000000000005', 'f1000000-0000-0000-0000-00000000000f',
   'Rap watched 2', (select id from public.genres where slug = 'hip-hop'),
   'f1000000-0000-0000-0000-00000000000f/v5.mp4', 60, 1000000, 'published',
   now() - interval '20 days', now() - interval '20 days');

-- V6 : pop, très tendance (30 vues récentes), jamais regardée par le fan de
-- rap -- doit perdre face à V7 malgré un meilleur score de tendance brut.
insert into public.videos
  (id, artist_id, title, genre_id, video_path, duration_seconds, size_bytes, status, published_at, created_at)
values (
  '10000000-0000-0000-0000-000000000006',
  'f1000000-0000-0000-0000-00000000000f',
  'Pop très tendance',
  (select id from public.genres where slug = 'pop'),
  'f1000000-0000-0000-0000-00000000000f/v6.mp4',
  60, 1000000, 'published', now() - interval '1 day', now() - interval '1 day'
);

-- V7 : hip-hop, jamais regardée par le fan de rap, peu de vues propres --
-- doit pourtant remonter en tête de ses recommandations grâce à l'affinité
-- de genre acquise via V4/V5.
insert into public.videos
  (id, artist_id, title, genre_id, video_path, duration_seconds, size_bytes, status, published_at, created_at)
values (
  '10000000-0000-0000-0000-000000000007',
  'f1000000-0000-0000-0000-00000000000f',
  'Rap jamais vu, à recommander',
  (select id from public.genres where slug = 'hip-hop'),
  'f1000000-0000-0000-0000-00000000000f/v7.mp4',
  60, 1000000, 'published', now() - interval '10 days', now() - interval '10 days'
);

-- ---------------------------------------------------------------------------
-- view_events (insérés directement, hors RPC record_view -- postgres
-- contourne l'absence de politique INSERT, comme pour les autres fixtures).
-- ---------------------------------------------------------------------------
-- V1 : 500 vues, toutes il y a 10 jours (hors fenêtre 7j).
insert into public.view_events (video_id, session_key, watched_seconds, created_at)
select '10000000-0000-0000-0000-000000000001', 'v1sess' || g, 30, now() - interval '10 days'
  from generate_series(1, 500) as g;

-- V2 : 20 vues d'hier (dans la fenêtre).
insert into public.view_events (video_id, session_key, watched_seconds, created_at)
select '10000000-0000-0000-0000-000000000002', 'v2sess' || g, 30, now() - interval '1 day'
  from generate_series(1, 20) as g;

-- V3 : 15 vues d'hier (dans la fenêtre) -- doit apparaître en tendances
-- AVANT le retrait testé plus bas.
insert into public.view_events (video_id, session_key, watched_seconds, created_at)
select '10000000-0000-0000-0000-000000000003', 'v3sess' || g, 30, now() - interval '1 day'
  from generate_series(1, 15) as g;

-- V6 : 30 vues récentes (score de tendance élevé).
insert into public.view_events (video_id, session_key, watched_seconds, created_at)
select '10000000-0000-0000-0000-000000000006', 'v6sess' || g, 30, now() - interval '1 day'
  from generate_series(1, 30) as g;

-- Le fan de rap (f2) regarde V4 et V5 plusieurs fois sur les 30 derniers
-- jours -- construit son affinité hip-hop (>= 3 vues, sort du démarrage à
-- froid) sans jamais avoir vu V7.
insert into public.view_events (video_id, user_id, watched_seconds, created_at)
values
  ('10000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-00000000000f', 30, now() - interval '5 days'),
  ('10000000-0000-0000-0000-000000000004', 'f2000000-0000-0000-0000-00000000000f', 30, now() - interval '4 days'),
  ('10000000-0000-0000-0000-000000000005', 'f2000000-0000-0000-0000-00000000000f', 30, now() - interval '3 days'),
  ('10000000-0000-0000-0000-000000000005', 'f2000000-0000-0000-0000-00000000000f', 30, now() - interval '2 days');

-- ---------------------------------------------------------------------------
-- Premier rafraîchissement (non concurrent -- la vue vient d'être créée
-- vide de ces données de test, refresh_trending_videos() gère les deux cas).
-- ---------------------------------------------------------------------------
select public.refresh_trending_videos();

-- ---------------------------------------------------------------------------
-- 1) et 2) Fenêtre de 7 jours respectée par trending_videos_feed().
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-00000000000f","role":"authenticated"}', true);

do $$
declare
  v_old_present  boolean;
  v_recent_present boolean;
begin
  select exists (
    select 1 from public.trending_videos_feed(100, null) t
     where t.id = '10000000-0000-0000-0000-000000000001'
  ) into v_old_present;

  if v_old_present then
    raise exception 'ÉCHEC : la vidéo à 500 vues datant de 10 jours ne devrait PAS être en tendances.';
  end if;
  raise notice 'SUCCES : vidéo à 500 vues (10 jours, hors fenêtre) absente des tendances.';

  select exists (
    select 1 from public.trending_videos_feed(100, null) t
     where t.id = '10000000-0000-0000-0000-000000000002'
  ) into v_recent_present;

  if not v_recent_present then
    raise exception 'ÉCHEC : la vidéo à 20 vues d''hier devrait être en tendances.';
  end if;
  raise notice 'SUCCES : vidéo à 20 vues d''hier présente en tendances.';
end $$;

-- ---------------------------------------------------------------------------
-- 3) TEST DÉCISIF : retrait sans refresh -> disparition immédiate.
-- ---------------------------------------------------------------------------
do $$
declare
  v_present_before boolean;
begin
  select exists (
    select 1 from public.trending_videos_feed(100, null) t
     where t.id = '10000000-0000-0000-0000-000000000003'
  ) into v_present_before;

  if not v_present_before then
    raise exception 'ÉCHEC (préalable) : V3 devrait être en tendances avant son retrait.';
  end if;
end $$;

-- Retrait par la modération (transition réservée à service_role/postgres,
-- exemptée par videos_guard_client_fields).
reset role;
update public.videos set status = 'removed'
 where id = '10000000-0000-0000-0000-000000000003';

-- AUCUN refresh materialized view ici : c'est tout le sens du test.
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"f2000000-0000-0000-0000-00000000000f","role":"authenticated"}', true);

do $$
declare
  v_present_after boolean;
begin
  select exists (
    select 1 from public.trending_videos_feed(100, null) t
     where t.id = '10000000-0000-0000-0000-000000000003'
  ) into v_present_after;

  if v_present_after then
    raise exception
      'ÉCHEC : V3 retirée (removed) mais toujours visible via trending_videos_feed() -- '
      'le montage à deux étages ne réapplique pas le statut à la lecture.';
  end if;
  raise notice
    'SUCCES (test décisif) : V3 passée à removed disparaît IMMÉDIATEMENT de '
    'trending_videos_feed(), SANS refresh de la vue matérialisée.';
end $$;

-- ---------------------------------------------------------------------------
-- 4) Affinité de genre : le fan de rap reçoit du rap en tête, y compris une
--    vidéo jamais vue (V7), devant une vidéo pop plus tendante (V6).
-- ---------------------------------------------------------------------------
-- On s'appuie sur `with ordinality` pour capter l'ordre RÉEL retourné par
-- recommended_videos() (déjà trié par score desc en interne) : un simple
-- ORDER BY additionnel sur une autre colonne (ex. id) écraserait ce tri.
do $$
declare
  v_top_id    uuid;
  v_top_genre integer;
  v_hiphop_id integer;
  v_v7_rank   integer;
  v_v6_rank   integer;
begin
  select id into v_hiphop_id from public.genres where slug = 'hip-hop';

  select r.id, r.genre_id
    into v_top_id, v_top_genre
    from public.recommended_videos(10) with ordinality as r(
      id, artist_id, title, description, genre_id, video_path, thumbnail_path,
      duration_seconds, size_bytes, status, moderation_result, view_count,
      like_count, comment_count, published_at, created_at, artist, rn
    )
   order by rn
   limit 1;

  if v_top_genre <> v_hiphop_id then
    raise exception
      'ÉCHEC : le premier résultat de recommended_videos() pour le fan de rap '
      'devrait être de genre hip-hop (id %), obtenu genre_id %.', v_hiphop_id, v_top_genre;
  end if;
  raise notice 'SUCCES : premier résultat de recommended_videos() en genre hip-hop (id %).', v_top_genre;

  select min(rn) into v_v7_rank
    from public.recommended_videos(10) with ordinality as r(
      id, artist_id, title, description, genre_id, video_path, thumbnail_path,
      duration_seconds, size_bytes, status, moderation_result, view_count,
      like_count, comment_count, published_at, created_at, artist, rn
    )
   where r.id = '10000000-0000-0000-0000-000000000007';

  select min(rn) into v_v6_rank
    from public.recommended_videos(10) with ordinality as r(
      id, artist_id, title, description, genre_id, video_path, thumbnail_path,
      duration_seconds, size_bytes, status, moderation_result, view_count,
      like_count, comment_count, published_at, created_at, artist, rn
    )
   where r.id = '10000000-0000-0000-0000-000000000006';

  if v_v7_rank is null then
    raise exception 'ÉCHEC : V7 (hip-hop, jamais vue) devrait apparaître dans les recommandations.';
  end if;

  if v_v6_rank is null or v_v7_rank >= v_v6_rank then
    raise exception
      'ÉCHEC : V7 (affinité hip-hop, rang %) devrait être classée AVANT V6 (pop tendante, rang %).',
      v_v7_rank, v_v6_rank;
  end if;
  raise notice
    'SUCCES : V7 (hip-hop, affinité, rang %) classée avant V6 (pop tendante, rang %).',
    v_v7_rank, v_v6_rank;
end $$;

-- ---------------------------------------------------------------------------
-- 5) Compte neuf (aucun view_events) = exactement trending_videos_feed().
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"f3000000-0000-0000-0000-00000000000f","role":"authenticated"}', true);

do $$
declare
  v_reco   uuid[];
  v_trend  uuid[];
begin
  select array_agg(id) into v_reco from public.recommended_videos(20);
  select array_agg(id) into v_trend from public.trending_videos_feed(20, null);

  if v_reco is distinct from v_trend then
    raise exception
      'ÉCHEC : un compte neuf devrait recevoir EXACTEMENT trending_videos_feed(), '
      'obtenu des listes différentes (% vs %).', v_reco, v_trend;
  end if;
  raise notice 'SUCCES : compte neuf reçoit exactement trending_videos_feed() (% clip(s)).',
    coalesce(array_length(v_reco, 1), 0);
end $$;

-- ---------------------------------------------------------------------------
-- 6) anon peut appeler les deux fonctions sans erreur.
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  v_count1 integer;
  v_count2 integer;
begin
  select count(*) into v_count1 from public.trending_videos_feed(20, null);
  select count(*) into v_count2 from public.recommended_videos(20);

  raise notice
    'SUCCES : anon appelle trending_videos_feed() (% ligne(s)) et recommended_videos() (% ligne(s)) sans erreur.',
    v_count1, v_count2;
end $$;

reset role;
rollback;
