-- =========================================================================
-- Test RLS — table profiles
-- Démontre qu'un utilisateur A ne peut NI lire NI modifier le profil d'un
-- utilisateur B, mais peut lire/modifier le sien.
--
-- Exécution (stack locale démarrée) :
--   psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')" \
--        -f supabase/tests/rls_profiles_test.sql
-- ou, plus simple :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/rls_profiles_test.sql
--
-- Le script s'exécute dans une transaction annulée à la fin (rollback) :
-- il ne laisse aucune donnée derrière lui.
-- =========================================================================

begin;

-- Deux utilisateurs de test (le trigger handle_new_user crée leurs profils).
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'authenticated', 'authenticated', 'alice@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"alice_test"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   'authenticated', 'authenticated', 'bob@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"bob_test"}'::jsonb);

-- --- On se fait passer pour Alice (rôle authenticated + claim sub = A) ---
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}',
  true
);

do $$
declare
  n_total    int;
  n_bob      int;
  n_updated  int;
begin
  -- 1) Alice ne voit QUE sa propre ligne.
  select count(*) into n_total from public.profiles;
  if n_total <> 1 then
    raise exception 'ÉCHEC : Alice voit % profils (attendu 1).', n_total;
  end if;

  -- 2) Alice ne peut pas lire le profil de Bob.
  select count(*) into n_bob
  from public.profiles
  where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if n_bob <> 0 then
    raise exception 'ÉCHEC : Alice lit le profil de Bob (% lignes).', n_bob;
  end if;

  -- 3) Alice ne peut pas modifier le profil de Bob (0 ligne affectée par RLS).
  update public.profiles
     set bio = 'piraté'
   where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  get diagnostics n_updated = row_count;
  if n_updated <> 0 then
    raise exception 'ÉCHEC : Alice a modifié le profil de Bob.';
  end if;

  -- 4) Alice PEUT modifier son propre profil.
  update public.profiles
     set bio = 'Coucou, c''est Alice'
   where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics n_updated = row_count;
  if n_updated <> 1 then
    raise exception 'ÉCHEC : Alice ne peut pas modifier son propre profil.';
  end if;

  raise notice '✅ SUCCÈS : isolation RLS des profils vérifiée (lecture + écriture).';
end $$;

-- --- Vérifie aussi l'anti-escalade de rôle ---
do $$
begin
  begin
    update public.profiles
       set role = 'admin'
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    raise exception 'ÉCHEC : Alice a pu se promouvoir admin.';
  exception
    when insufficient_privilege then
      raise notice '✅ SUCCÈS : escalade de rôle bloquée (Alice reste listener).';
  end;
end $$;

-- --- Vérifie l'anti-escalade à l'INSERT (défense en profondeur) ---
-- On prépare un utilisateur sans profil (superuser), puis Bob tente de créer
-- son profil avec role = 'admin' : le trigger doit forcer 'listener'.
reset role;
delete from public.profiles where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}',
  true
);

do $$
declare
  inserted_role public.user_role;
begin
  insert into public.profiles (id, username, role)
  values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob_test', 'admin')
  returning role into inserted_role;

  if inserted_role <> 'listener' then
    raise exception
      'ÉCHEC : Bob s''est auto-attribué le rôle % à l''inscription.', inserted_role;
  end if;
  raise notice '✅ SUCCÈS : rôle forcé à listener à l''INSERT (anti-escalade en profondeur).';
end $$;

reset role;
rollback;
