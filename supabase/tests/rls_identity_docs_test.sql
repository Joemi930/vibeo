-- =========================================================================
-- Test RLS — storage bucket identity-docs (Phase 4, lot L2).
-- Démontre :
--   1. Insertion dans le dossier d'autrui refusée.
--   2. Insertion dans son propre dossier acceptée.
--   3. SELECT sur le bucket en tant qu'ADMIN -> 0 ligne (aucune politique
--      admin, décision délibérée §4).
--   4. SELECT sur le bucket en tant que PROPRIÉTAIRE -> 0 ligne (aucune
--      politique select_own, contrairement à avatars/playlist-covers).
--   5. SELECT sur le bucket en tant que anon -> 0 ligne.
--
-- CONTRE-ÉPREUVE (section finale, dans une transaction imbriquée annulée par
-- ROLLBACK TO SAVEPOINT) : ajoute une politique SELECT `is_admin()` sur le
-- bucket, prouve qu'elle rendrait l'objet visible à l'admin, puis l'annule --
-- ceci démontre que le test ci-dessus discrimine réellement une politique
-- faible d'une absence de politique.
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/rls_identity_docs_test.sql
-- =========================================================================

begin;

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'e1000000-0000-0000-0000-00000000000e',
   'authenticated', 'authenticated', 'id_owner@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"id_owner"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'e2000000-0000-0000-0000-00000000000e',
   'authenticated', 'authenticated', 'id_other@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"id_other"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'e3000000-0000-0000-0000-00000000000e',
   'authenticated', 'authenticated', 'id_admin@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"id_admin"}'::jsonb);

update public.profiles set role = 'admin' where id = 'e3000000-0000-0000-0000-00000000000e';

-- ---------------------------------------------------------------------------
-- 1) Insertion dans le dossier d'autrui refusée.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e2000000-0000-0000-0000-00000000000e","role":"authenticated"}', true);

do $$
begin
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values (
      'identity-docs',
      'e1000000-0000-0000-0000-00000000000e/id-front.jpg',
      'e2000000-0000-0000-0000-00000000000e',
      '{"size": 1000, "mimetype": "image/jpeg"}'::jsonb
    );
    raise exception 'ÉCHEC : l''insertion dans le dossier d''autrui aurait dû être refusée.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : insertion dans le dossier d''autrui refusée (insufficient_privilege).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Insertion dans son propre dossier acceptée.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-00000000000e","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  insert into storage.objects (bucket_id, name, owner, metadata)
  values (
    'identity-docs',
    'e1000000-0000-0000-0000-00000000000e/id-front.jpg',
    'e1000000-0000-0000-0000-00000000000e',
    '{"size": 1000, "mimetype": "image/jpeg"}'::jsonb
  );

  select count(*) into v_count from storage.objects
   where bucket_id = 'identity-docs'
     and name = 'e1000000-0000-0000-0000-00000000000e/id-front.jpg';

  -- Le SELECT ci-dessus est fait par le même propriétaire juste après
  -- l'INSERT ; on vérifie ici seulement que l'INSERT n'a pas levé d'erreur
  -- (v_count peut être 0 puisqu'aucune politique SELECT n'existe -- voir
  -- assertion 4 plus bas qui le démontre explicitement).
  raise notice 'SUCCES : insertion dans son propre dossier acceptée (v_count post-insert via SELECT non garanti = %, voir assertion 4).', v_count;
end $$;

-- ---------------------------------------------------------------------------
-- 3) SELECT en tant qu'ADMIN -> 0 ligne (aucune politique admin, §4).
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-00000000000e","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from storage.objects where bucket_id = 'identity-docs';
  if v_count <> 0 then
    raise exception 'ÉCHEC : un admin ne devrait voir aucun objet identity-docs (aucune politique SELECT admin), obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : admin lit 0 ligne sur identity-docs (aucune politique SELECT admin -- décision délibérée §4).';
end $$;

-- ---------------------------------------------------------------------------
-- 4) SELECT en tant que PROPRIÉTAIRE -> 0 ligne (aucune politique select_own).
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-00000000000e","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from storage.objects where bucket_id = 'identity-docs';
  if v_count <> 0 then
    raise exception 'ÉCHEC : le propriétaire lui-même ne devrait voir aucun objet identity-docs (aucune politique SELECT), obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : propriétaire lit 0 ligne sur identity-docs (aucune politique SELECT, même pour lui-même).';
end $$;

-- ---------------------------------------------------------------------------
-- 5) SELECT en tant que anon -> 0 ligne.
-- ---------------------------------------------------------------------------
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from storage.objects where bucket_id = 'identity-docs';
  if v_count <> 0 then
    raise exception 'ÉCHEC : anon ne devrait voir aucun objet identity-docs, obtenu %.', v_count;
  end if;
  raise notice 'SUCCES : anon lit 0 ligne sur identity-docs.';
end $$;

-- =========================================================================
-- CONTRE-ÉPREUVE : le test ci-dessus discrimine-t-il vraiment une politique
-- faible d'une absence de politique ? On ajoute temporairement une politique
-- SELECT `is_admin()`, on prouve qu'elle rend l'objet visible à l'admin, puis
-- on l'annule via SAVEPOINT/ROLLBACK TO -- elle ne doit PAS survivre au COMMIT
-- final (qui de toute façon n'a pas lieu : tout le script se termine par
-- ROLLBACK).
-- =========================================================================
reset role;
savepoint counter_proof;

create policy identity_docs_storage_select_admin_TEMP_COUNTERPROOF
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'identity-docs' and public.is_admin());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-00000000000e","role":"authenticated"}', true);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from storage.objects where bucket_id = 'identity-docs';
  if v_count <> 1 then
    raise exception
      'ÉCHEC CONTRE-ÉPREUVE : avec une politique is_admin() ajoutée, l''admin devrait voir 1 ligne, obtenu %. '
      'Le test principal ne discriminerait donc pas correctement une politique faible.', v_count;
  end if;
  raise notice
    'SUCCES CONTRE-ÉPREUVE : avec une politique is_admin() temporaire, l''admin voit bien % ligne(s) -- '
    'ce qui prouve que l''absence de politique (testée plus haut) est la cause réelle du 0 obtenu, pas un '
    'artefact du test.', v_count;
end $$;

reset role;
rollback to savepoint counter_proof;

reset role;
rollback;
