-- =========================================================================
-- Test RLS — moderation_logs + reports.priority (Phase 4, lot L1).
-- Démontre :
--   1. Un non-admin lit 0 ligne de moderation_logs.
--   2. Un admin lit les lignes de moderation_logs (insérées en service_role
--      via `set local role postgres`, seul rôle exempté disponible en psql).
--   3. Un INSERT en `authenticated` échoue (aucun grant insert/update/delete).
--   4. `anon` lit 0 ligne.
--   5. Un signalement hate_speech obtient une priorité strictement supérieure
--      à un signalement spam (motifs différents, même cible neuve).
--   6. Un second signalement (par un autre utilisateur) sur la MÊME cible
--      fait monter la priorité (bonus signalement concurrent).
--   7. Un client ne peut pas remonter priority par UPDATE (figée à old.priority).
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/rls_moderation_logs_test.sql
-- =========================================================================

begin;

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'a1000000-0000-0000-0000-00000000000a',
   'authenticated', 'authenticated', 'ml_a@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"ml_listener_a"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'a2000000-0000-0000-0000-00000000000a',
   'authenticated', 'authenticated', 'ml_b@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"ml_listener_b"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'a3000000-0000-0000-0000-00000000000a',
   'authenticated', 'authenticated', 'ml_artist@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"ml_artist"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'a4000000-0000-0000-0000-00000000000a',
   'authenticated', 'authenticated', 'ml_admin@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"ml_admin"}'::jsonb);

update public.profiles set role = 'artist' where id = 'a3000000-0000-0000-0000-00000000000a';
update public.profiles set role = 'admin'  where id = 'a4000000-0000-0000-0000-00000000000a';

-- Deux clips publiés de l'artiste, pour les signalements ci-dessous.
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a3000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

-- Depuis 20260727010400_moderation_gate.sql (verrou de modération, Phase 4),
-- un client ne peut plus créer un clip directement en `published` : seul
-- `processing` est autorisé à l'INSERT. On insère donc en `processing` puis
-- on simule la décision de modération (service_role) en passant par le rôle
-- `postgres`, exempté par le trigger -- même patron que les autres fixtures
-- de ce fichier pour moderation_logs.
insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes, status)
values (
  'b1000000-0000-0000-0000-00000000000b',
  'a3000000-0000-0000-0000-00000000000a',
  'Clip modération 1',
  'a3000000-0000-0000-0000-00000000000a/clip1.mp4',
  60, 1000000, 'processing'
);

insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes, status)
values (
  'b2000000-0000-0000-0000-00000000000b',
  'a3000000-0000-0000-0000-00000000000a',
  'Clip modération 2',
  'a3000000-0000-0000-0000-00000000000a/clip2.mp4',
  60, 1000000, 'processing'
);

-- Décision de modération simulée (service_role) : publication des deux clips.
reset role;
update public.videos set status = 'published'
 where id in ('b1000000-0000-0000-0000-00000000000b', 'b2000000-0000-0000-0000-00000000000b');

-- Une ligne de moderation_logs, insérée sous rôle `postgres` (le seul rôle
-- d'administration accessible depuis psql, exempté par les gardes-fous et non
-- soumis à la RLS -- même raccourci que les autres fichiers de test pour
-- représenter une écriture service_role).
insert into public.moderation_logs (actor, actor_id, target_type, target_id, action, reason)
values ('admin', 'a4000000-0000-0000-0000-00000000000a', 'video',
        'b1000000-0000-0000-0000-00000000000b', 'warn_author', 'Test');

-- ---------------------------------------------------------------------------
-- 1) Non-admin lit 0 ligne.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.moderation_logs;
  if v_count <> 0 then
    raise exception 'ÉCHEC : un non-admin ne devrait lire aucune ligne de moderation_logs, obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : non-admin lit 0 ligne de moderation_logs.';
end $$;

-- INSERT en authenticated doit échouer (aucun grant).
do $$
begin
  begin
    insert into public.moderation_logs (actor, target_type, target_id, action)
    values ('admin', 'video', 'b1000000-0000-0000-0000-00000000000b', 'hack_attempt');
    raise exception 'ÉCHEC : un INSERT authenticated sur moderation_logs aurait dû échouer.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : INSERT authenticated sur moderation_logs refusé (insufficient_privilege).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Admin lit les lignes.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a4000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.moderation_logs;
  if v_count < 1 then
    raise exception 'ÉCHEC : un admin devrait lire au moins 1 ligne de moderation_logs, obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : admin lit % ligne(s) de moderation_logs.', v_count;
end $$;

-- ---------------------------------------------------------------------------
-- 4) anon lit 0 ligne.
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

-- anon n'a même pas de GRANT SELECT sur moderation_logs (règle : jamais à
-- anon, voir migration) : PostgREST/psql renvoie "permission denied" avant
-- même d'évaluer la RLS. On accepte ce refus au niveau GRANT comme un succès
-- équivalent à "0 ligne visible" -- le résultat pour l'utilisateur est
-- identique (aucune donnée), la cause est juste encore plus stricte.
do $$
declare
  v_count integer;
begin
  begin
    select count(*) into v_count from public.moderation_logs;
    if v_count <> 0 then
      raise exception 'ÉCHEC : anon ne devrait lire aucune ligne de moderation_logs, obtenu %.', v_count;
    end if;
    raise notice 'SUCCES : anon lit 0 ligne de moderation_logs.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : anon n''a même pas le GRANT SELECT sur moderation_logs (insufficient_privilege).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 5) Priorité : hate_speech > spam sur des cibles neuves distinctes.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

insert into public.reports (reporter_id, video_id, reason)
values ('a1000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-00000000000b', 'hate_speech');

insert into public.reports (reporter_id, video_id, reason)
values ('a1000000-0000-0000-0000-00000000000a', 'b2000000-0000-0000-0000-00000000000b', 'spam');

reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a4000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare
  v_hate integer;
  v_spam integer;
begin
  select priority into v_hate from public.reports
   where video_id = 'b1000000-0000-0000-0000-00000000000b' and reason = 'hate_speech';
  select priority into v_spam from public.reports
   where video_id = 'b2000000-0000-0000-0000-00000000000b' and reason = 'spam';

  if not (v_hate > v_spam) then
    raise exception 'ÉCHEC : priorité hate_speech (%) devrait être > priorité spam (%).', v_hate, v_spam;
  end if;
  raise notice 'SUCCES : priorité hate_speech (%) > priorité spam (%).', v_hate, v_spam;
end $$;

-- ---------------------------------------------------------------------------
-- 6) Un second signalement sur la même cible fait monter la priorité.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

insert into public.reports (reporter_id, video_id, reason)
values ('a2000000-0000-0000-0000-00000000000a', 'b1000000-0000-0000-0000-00000000000b', 'hate_speech');

reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a4000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare
  v_first  integer;
  v_second integer;
begin
  select priority into v_first from public.reports
   where video_id = 'b1000000-0000-0000-0000-00000000000b' and reporter_id = 'a1000000-0000-0000-0000-00000000000a';
  select priority into v_second from public.reports
   where video_id = 'b1000000-0000-0000-0000-00000000000b' and reporter_id = 'a2000000-0000-0000-0000-00000000000a';

  if not (v_second > v_first) then
    raise exception 'ÉCHEC : priorité du 2e signalement (%) devrait être > au 1er (%) sur la même cible.', v_second, v_first;
  end if;
  raise notice 'SUCCES : priorité montée sur signalement concurrent (% -> %).', v_first, v_second;
end $$;

-- ---------------------------------------------------------------------------
-- 7) Un client (admin, seul rôle pouvant UPDATE reports) ne peut pas
--    remonter priority par UPDATE : elle reste figée à old.priority.
-- ---------------------------------------------------------------------------
do $$
declare
  v_before integer;
  v_after  integer;
begin
  select priority into v_before from public.reports
   where video_id = 'b2000000-0000-0000-0000-00000000000b' and reason = 'spam';

  update public.reports set priority = 127
   where video_id = 'b2000000-0000-0000-0000-00000000000b' and reason = 'spam';

  select priority into v_after from public.reports
   where video_id = 'b2000000-0000-0000-0000-00000000000b' and reason = 'spam';

  if v_after <> v_before then
    raise exception 'ÉCHEC : priority aurait dû rester à % (figée), obtenu %.', v_before, v_after;
  end if;
  raise notice 'SUCCES : priority figée par UPDATE (reste à %).', v_after;
end $$;

reset role;
rollback;
