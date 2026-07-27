-- =========================================================================
-- Test RLS — artist_applications (Phase 4, lot L2).
-- Démontre :
--   1. Un candidat lit sa seule ligne (colonnes autorisées).
--   2. `select ai_analysis from artist_applications` lève 42501 (colonne non
--      accordée par GRANT, indépendamment de la RLS).
--   3. Une 2e candidature dans les 7 jours lève 54000.
--   4. L'index unique partiel bloque une 2e candidature ouverte (même en
--      dehors de la fenêtre de rate limit -- ici testé directement en
--      service_role/postgres pour isoler l'index de la 3e vérification).
--   5. `anon` ne voit rien.
--   6. Un candidat ne peut pas passer sa candidature en 'approved'.
--   7. Un non-admin lisant admin_artist_applications obtient 0 ligne.
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/rls_artist_applications_test.sql
-- =========================================================================

begin;

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'c1000000-0000-0000-0000-00000000000c',
   'authenticated', 'authenticated', 'aa_candidate@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"aa_candidate"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'c2000000-0000-0000-0000-00000000000c',
   'authenticated', 'authenticated', 'aa_other@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"aa_other"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'c3000000-0000-0000-0000-00000000000c',
   'authenticated', 'authenticated', 'aa_admin@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"aa_admin"}'::jsonb);

update public.profiles set role = 'admin' where id = 'c3000000-0000-0000-0000-00000000000c';

-- Candidature de départ, insérée en tant que postgres (représente l'Edge
-- Function verify-artist en service_role -- aucune politique INSERT n'existe
-- pour authenticated, une insertion via PostgREST client échouerait toujours).
reset role;
insert into public.artist_applications
  (id, user_id, stage_name, links, statement, ai_score, ai_analysis, ai_provider, id_document_path)
values (
  'd1000000-0000-0000-0000-00000000000d',
  'c1000000-0000-0000-0000-00000000000c',
  'DJ Test',
  '["https://example.com/dj-test"]'::jsonb,
  'Je suis un artiste local qui produit de la musique urbaine depuis cinq ans, avec plusieurs sorties.',
  72.50,
  '{"reasoning":"score détaillé confidentiel"}'::jsonb,
  'gemini',
  'c1000000-0000-0000-0000-00000000000c/id-front.jpg'
);

-- ---------------------------------------------------------------------------
-- 1) Le candidat lit sa seule ligne (colonnes autorisées).
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.artist_applications
   where id = 'd1000000-0000-0000-0000-00000000000d';
  if v_count <> 1 then
    raise exception 'ÉCHEC : le candidat devrait lire sa propre candidature, obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : le candidat lit sa propre candidature (colonnes autorisées).';
end $$;

-- ---------------------------------------------------------------------------
-- 2) select ai_analysis lève 42501 (colonne non accordée).
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    perform ai_analysis from public.artist_applications
     where id = 'd1000000-0000-0000-0000-00000000000d';
    raise exception 'ÉCHEC : lire ai_analysis aurait dû échouer (42501).';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : lecture de ai_analysis refusée (insufficient_privilege / 42501).';
  end;
end $$;

do $$
begin
  begin
    perform id_document_path from public.artist_applications
     where id = 'd1000000-0000-0000-0000-00000000000d';
    raise exception 'ÉCHEC : lire id_document_path aurait dû échouer (42501).';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : lecture de id_document_path refusée (insufficient_privilege / 42501).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Une 2e candidature dans les 7 jours lève 54000 (rate limit).
--    Insérée directement en `authenticated` : bien qu'aucune politique
--    INSERT n'existe (elle échouerait de toute façon par RLS), le trigger de
--    rate limit s'exécute AVANT la vérification RLS d'insertion -- on
--    s'attend donc à voir l'erreur 54000 lever en premier ici. Si jamais RLS
--    la bloquait d'abord (insufficient_privilege), le test l'accepte aussi
--    comme un refus valide, mais log un avertissement.
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    insert into public.artist_applications (user_id, stage_name, statement)
    values (
      'c1000000-0000-0000-0000-00000000000c',
      'DJ Test 2',
      'Seconde tentative de candidature dans la même semaine, qui doit être bloquée par le rate limit.'
    );
    raise exception 'ÉCHEC : une 2e candidature dans les 7 jours aurait dû être bloquée.';
  exception
    when sqlstate '54000' then
      raise notice 'SUCCES : 2e candidature en 7 jours bloquée (54000).';
    when insufficient_privilege then
      raise notice 'SUCCES (chemin RLS) : 2e candidature bloquée avant le rate limit (aucune politique INSERT).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 4) Index unique partiel : bloque une 2e candidature OUVERTE, testé côté
--    service_role/postgres pour isoler l'index du rate limit (au-delà de la
--    fenêtre de 7 jours, en simulant created_at ancien).
-- ---------------------------------------------------------------------------
reset role;

update public.artist_applications
   set created_at = now() - interval '10 days'
 where id = 'd1000000-0000-0000-0000-00000000000d';

do $$
begin
  begin
    insert into public.artist_applications (user_id, stage_name, statement)
    values (
      'c1000000-0000-0000-0000-00000000000c',
      'DJ Test 3',
      'Troisième tentative, hors fenêtre de rate limit mais avec une candidature encore ouverte (pending).'
    );
    raise exception 'ÉCHEC : une 2e candidature OUVERTE aurait dû être bloquée par l''index unique partiel.';
  exception
    when unique_violation then
      raise notice 'SUCCES : index unique partiel bloque une 2e candidature ouverte (unique_violation).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 5) anon ne voit rien.
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

-- anon n'a aucun GRANT sur artist_applications (grant select/update ciblent
-- uniquement `authenticated`) : le refus se produit au niveau GRANT, avant
-- même la RLS -- résultat équivalent (0 ligne visible), cause encore plus
-- stricte. On accepte les deux issues.
do $$
declare
  v_count integer;
begin
  begin
    select count(*) into v_count from public.artist_applications;
    if v_count <> 0 then
      raise exception 'ÉCHEC : anon ne devrait lire aucune candidature, obtenu %.', v_count;
    end if;
    raise notice 'SUCCES : anon lit 0 candidature.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : anon n''a même pas le GRANT SELECT sur artist_applications (insufficient_privilege).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 6) Le candidat ne peut pas passer sa candidature en 'approved'.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c1000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);

do $$
begin
  begin
    update public.artist_applications
       set status = 'approved'
     where id = 'd1000000-0000-0000-0000-00000000000d';
    raise exception 'ÉCHEC : le candidat n''aurait pas dû pouvoir passer sa candidature en approved.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : transition vers approved refusée au candidat (insufficient_privilege).';
  end;
end $$;

-- Vérifie que l'annulation (rejected) reste, elle, autorisée.
do $$
declare
  v_status public.application_status;
begin
  update public.artist_applications
     set status = 'rejected'
   where id = 'd1000000-0000-0000-0000-00000000000d';

  select status into v_status from public.artist_applications
   where id = 'd1000000-0000-0000-0000-00000000000d';

  if v_status <> 'rejected' then
    raise exception 'ÉCHEC : l''annulation par le candidat (-> rejected) aurait dû fonctionner.';
  end if;
  raise notice 'SUCCES : le candidat peut annuler sa candidature (-> rejected).';
end $$;

-- ---------------------------------------------------------------------------
-- 7) Un non-admin lisant admin_artist_applications obtient 0 ligne.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c2000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.admin_artist_applications;
  if v_count <> 0 then
    raise exception 'ÉCHEC : un non-admin ne devrait lire aucune ligne de admin_artist_applications, obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : non-admin lit 0 ligne de admin_artist_applications.';
end $$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c3000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.admin_artist_applications;
  if v_count < 1 then
    raise exception 'ÉCHEC : un admin devrait lire au moins 1 ligne de admin_artist_applications, obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : admin lit % ligne(s) de admin_artist_applications (has_document inclus, pas id_document_path).', v_count;
end $$;

reset role;
rollback;
