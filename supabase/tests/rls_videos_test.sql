-- =========================================================================
-- Test RLS — table videos + RPC record_view
-- Démontre :
--   1. Un auditeur (listener) ne peut pas insérer de vidéo.
--   2. Un artiste peut insérer SA vidéo, mais pas au nom d'un autre artiste.
--   3. Une vidéo `processing` n'est visible que par son propriétaire ; une
--      fois `published`, elle l'est par tout le monde (y compris anon).
--   4. Le client ne peut pas modifier view_count / like_count (le trigger
--      restaure la valeur précédente).
--   5. record_view() applique la règle des 10 s et l'anti-spam (30 min).
--   6. La 6e publication d'un même artiste en 24h glissantes est bloquée
--      (errcode 54000).
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/rls_videos_test.sql
--
-- Le script s'exécute dans une transaction annulée à la fin (rollback) :
-- il ne laisse aucune donnée derrière lui.
-- =========================================================================

begin;

-- ---------------------------------------------------------------------------
-- Comptes de test (le trigger handle_new_user crée leurs profils en 'listener').
-- ---------------------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'cccccccc-cccc-cccc-cccc-cccccccccccc',
   'authenticated', 'authenticated', 'charlie@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"charlie_listener"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'dddddddd-dddd-dddd-dddd-dddddddddddd',
   'authenticated', 'authenticated', 'dave@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"dave_artist"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   'authenticated', 'authenticated', 'eve@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"eve_artist"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'ffffffff-ffff-ffff-ffff-ffffffffffff',
   'authenticated', 'authenticated', 'frank@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"frank_artist"}'::jsonb);

-- Promotion en 'artist' pour Dave, Eve, Frank (exécuté en tant que postgres,
-- exempté par prevent_role_escalation -- même raccourci que la migration
-- 20260725000000_seed_artist_role.sql).
update public.profiles
   set role = 'artist'
 where id in (
   'dddddddd-dddd-dddd-dddd-dddddddddddd',
   'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
   'ffffffff-ffff-ffff-ffff-ffffffffffff'
 );

-- ---------------------------------------------------------------------------
-- 1) Un auditeur (listener) ne peut pas insérer de vidéo.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}',
  true
);

do $$
begin
  begin
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes)
    values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'Vidéo non-artiste',
      'cccccccc-cccc-cccc-cccc-cccccccccccc/clip.mp4',
      60, 1000000
    );
    raise exception 'ÉCHEC : un auditeur a pu insérer une vidéo.';
  exception
    when insufficient_privilege then
      raise notice '✅ SUCCÈS : un auditeur ne peut pas insérer de vidéo (videos_insert_own_artist).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Un artiste (Dave) insère SA vidéo -- succès.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}',
  true
);

do $$
declare
  v_status public.video_status;
begin
  insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes)
  values (
    '11111111-1111-1111-1111-111111111111',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'Clip de test',
    'dddddddd-dddd-dddd-dddd-dddddddddddd/clip.mp4',
    60, 1000000
  )
  returning status into v_status;

  if v_status <> 'processing' then
    raise exception 'ÉCHEC : statut initial inattendu (%).', v_status;
  end if;
  raise notice '✅ SUCCÈS : un artiste peut publier SA propre vidéo (statut initial processing).';
end $$;

-- 2bis) Dave tente d'insérer une vidéo au nom d'Eve -- doit échouer.
do $$
begin
  begin
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes)
    values (
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
      'Vidéo usurpée',
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/clip.mp4',
      60, 1000000
    );
    raise exception 'ÉCHEC : Dave a pu insérer une vidéo au nom d''Eve.';
  exception
    when insufficient_privilege then
      raise notice '✅ SUCCÈS : insertion au nom d''un autre artiste bloquée (videos_insert_own_artist).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Visibilité selon le statut.
-- ---------------------------------------------------------------------------
-- Charlie (tiers authentifié) ne voit pas la vidéo `processing` de Dave.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}',
  true
);

do $$
declare
  n int;
begin
  select count(*) into n
  from public.videos
  where id = '11111111-1111-1111-1111-111111111111';

  if n <> 0 then
    raise exception 'ÉCHEC : un tiers voit une vidéo en cours de traitement (processing).';
  end if;
  raise notice '✅ SUCCÈS : une vidéo processing n''est pas visible par un tiers.';
end $$;

-- Dave tente de publier LUI-MÊME sa vidéo -- doit désormais échouer.
--
-- INVERSION DÉLIBÉRÉE par rapport à la version Phase 2/3 de ce test : cette
-- section affirmait auparavant « l'artiste peut publier sa vidéo, published_at
-- renseigné automatiquement ». Depuis 20260727010400_moderation_gate.sql
-- (verrou de modération, Phase 4), c'est FAUX -- le client ne décide plus
-- d'AUCUNE transition de statut, dans aucun sens (la règle Phase 3 ne
-- bloquait que les transitions VERS un statut de modération ; elle est
-- maintenant totale). Un test qui affirmerait encore l'ancien comportement
-- masquerait une régression de sécurité au lieu de la détecter.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}',
  true
);

do $$
begin
  begin
    update public.videos
       set status = 'published'
     where id = '11111111-1111-1111-1111-111111111111';
    raise exception
      'ÉCHEC : l''artiste a pu publier lui-même sa vidéo -- le statut devrait '
      'être exclusivement réservé à la modération (moderate-video, service_role).';
  exception
    when insufficient_privilege then
      raise notice
        '✅ SUCCÈS : l''artiste ne peut pas publier lui-même sa vidéo (42501, '
        'verrou de modération Phase 4).';
  end;
end $$;

-- Publication simulée par moderate-video (service_role) : rôle `postgres`,
-- exempté par le trigger, pose le statut ET published_at explicitement --
-- le trigger ne le pose plus automatiquement pour les rôles exemptés.
reset role;
update public.videos
   set status = 'published', published_at = now()
 where id = '11111111-1111-1111-1111-111111111111';

-- Charlie (tiers authentifié) voit maintenant la vidéo publiée.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}',
  true
);

do $$
declare
  n int;
begin
  select count(*) into n
  from public.videos
  where id = '11111111-1111-1111-1111-111111111111';

  if n <> 1 then
    raise exception 'ÉCHEC : la vidéo publiée n''est pas visible par un tiers authentifié (% lignes).', n;
  end if;
  raise notice '✅ SUCCÈS : une vidéo published est visible par un tiers authentifié.';
end $$;

-- anon (non authentifié) voit aussi la vidéo publiée.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  n int;
begin
  select count(*) into n
  from public.videos
  where id = '11111111-1111-1111-1111-111111111111';

  if n <> 1 then
    raise exception 'ÉCHEC : la vidéo publiée n''est pas visible en anon (% lignes).', n;
  end if;
  raise notice '✅ SUCCÈS : une vidéo published est visible en anon (sans authentification).';
end $$;

-- ---------------------------------------------------------------------------
-- 4) Le client ne peut pas modifier view_count / like_count.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}',
  true
);

do $$
declare
  v_view_count bigint;
  v_like_count bigint;
begin
  update public.videos
     set view_count = 9999,
         like_count  = 9999
   where id = '11111111-1111-1111-1111-111111111111'
  returning view_count, like_count into v_view_count, v_like_count;

  if v_view_count <> 0 or v_like_count <> 0 then
    raise exception
      'ÉCHEC : le client a pu modifier les compteurs (view=%, like=%).', v_view_count, v_like_count;
  end if;
  raise notice '✅ SUCCÈS : les compteurs sont restaurés par le trigger videos_guard_client_fields.';
end $$;

-- ---------------------------------------------------------------------------
-- 5) record_view() : règle des 10 s + anti-spam 30 min.
-- ---------------------------------------------------------------------------
-- 5a) Moins de 10 s de lecture -> rejeté, compteur inchangé.
do $$
declare
  v_result     boolean;
  v_view_count bigint;
begin
  select public.record_view('11111111-1111-1111-1111-111111111111', 5) into v_result;
  if v_result is distinct from false then
    raise exception 'ÉCHEC : record_view a compté une vue de 5 secondes.';
  end if;

  select view_count into v_view_count
  from public.videos
  where id = '11111111-1111-1111-1111-111111111111';

  if v_view_count <> 0 then
    raise exception 'ÉCHEC : view_count modifié malgré un rejet (%).', v_view_count;
  end if;
  raise notice '✅ SUCCÈS : record_view rejette une vue de moins de 10 secondes.';
end $$;

-- 5b) 12 s de lecture -> comptée, view_count = 1.
do $$
declare
  v_result     boolean;
  v_view_count bigint;
begin
  select public.record_view('11111111-1111-1111-1111-111111111111', 12) into v_result;
  if v_result is distinct from true then
    raise exception 'ÉCHEC : record_view a rejeté une vue valide de 12 secondes.';
  end if;

  select view_count into v_view_count
  from public.videos
  where id = '11111111-1111-1111-1111-111111111111';

  if v_view_count <> 1 then
    raise exception 'ÉCHEC : view_count attendu à 1, obtenu %.', v_view_count;
  end if;
  raise notice '✅ SUCCÈS : record_view compte une vue valide (view_count incrémenté par trigger).';
end $$;

-- 5c) Rappel immédiat -> anti-spam, rejeté, view_count toujours 1.
do $$
declare
  v_result     boolean;
  v_view_count bigint;
begin
  select public.record_view('11111111-1111-1111-1111-111111111111', 12) into v_result;
  if v_result is distinct from false then
    raise exception 'ÉCHEC : anti-spam défaillant, une seconde vue rapprochée a été comptée.';
  end if;

  select view_count into v_view_count
  from public.videos
  where id = '11111111-1111-1111-1111-111111111111';

  if v_view_count <> 1 then
    raise exception 'ÉCHEC : view_count a changé lors du rappel immédiat (%).', v_view_count;
  end if;
  raise notice '✅ SUCCÈS : anti-spam de record_view (rappel immédiat rejeté, view_count inchangé).';
end $$;

-- ---------------------------------------------------------------------------
-- 6) Rate limiting : 5 vidéos / 24h / artiste, la 6e est bloquée (54000).
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"ffffffff-ffff-ffff-ffff-ffffffffffff","role":"authenticated"}',
  true
);

do $$
declare
  i int;
begin
  for i in 1..5 loop
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes)
    values (
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      'Clip quota ' || i,
      'ffffffff-ffff-ffff-ffff-ffffffffffff/clip_' || i || '.mp4',
      60, 1000000
    );
  end loop;
  raise notice '✅ SUCCÈS : 5 vidéos insérées sans blocage (quota journalier respecté).';
end $$;

do $$
begin
  begin
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes)
    values (
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      'Clip quota 6',
      'ffffffff-ffff-ffff-ffff-ffffffffffff/clip_6.mp4',
      60, 1000000
    );
    raise exception 'ÉCHEC : la 6e vidéo en 24h a été acceptée (quota non appliqué).';
  exception
    when sqlstate '54000' then
      raise notice '✅ SUCCÈS : la 6e publication en 24h glissantes est bloquée (errcode 54000).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 7) Un artiste ne peut pas revendiquer le FICHIER d'un autre artiste.
--
-- Sans la contrainte de propriété sur `video_path`, un artiste pouvait créer
-- une fiche `published` pointant vers le fichier encore privé d'un confrère :
-- la politique storage `videos_storage_select_published` devenait alors vraie
-- pour ce fichier et le rendait lisible par tout le monde. Faille identifiée
-- à l'audit de sécurité de la Phase 2.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}',
  true
);

do $$
begin
  begin
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes)
    values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'Clip volé',
      -- Chemin appartenant au dossier storage d'un AUTRE artiste.
      'dddddddd-dddd-dddd-dddd-dddddddddddd/clip_prive.mp4',
      60, 1000000
    );
    raise exception
      'ÉCHEC : un artiste a publié une fiche pointant vers le fichier d''un autre.';
  exception
    when insufficient_privilege then
      raise notice
        '✅ SUCCÈS : impossible de revendiquer le fichier storage d''un autre artiste.';
  end;
end $$;

reset role;
rollback;
