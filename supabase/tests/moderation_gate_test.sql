-- =========================================================================
-- Test RLS/fonctionnel — verrou de modération vidéo (Phase 4,
-- 20260727010400_moderation_gate.sql). Test dédié annoncé par cette
-- migration et qui manquait.
-- Démontre :
--   1. Un artiste insérant status='published' lève 42501.
--   2. Un artiste insérant status='pending_moderation' lève 42501.
--   3. Un artiste insérant status='processing' réussit, published_at NULL.
--   4. Le clip processing est invisible d'un tiers authentifié et d'anon.
--   5. Un artiste tentant `update ... set status='published'` sur SON clip
--      processing lève 42501.
--   6. LE CAS QUI COMPTE LE PLUS : un artiste dont le clip est `rejected` ne
--      peut pas le repasser en `published` lui-même.
--   7. Un artiste ne peut pas réécrire moderation_result (restauré par le
--      trigger).
--   8. Un artiste peut TOUJOURS modifier titre/description/miniature/genre
--      de son clip -- contre-épreuve que le verrou n'a rien cassé.
--   9. En reset role (rôle exempté, ce que fait moderate-video), la
--      transition processing -> published fonctionne.
--
-- CONTRE-ÉPREUVE FINALE (transaction imbriquée, SAVEPOINT/ROLLBACK TO) :
-- rétablit l'ANCIENNE version du trigger (celle de 20260726010000_social.sql,
-- qui autorisait `published` à la création et ne bloquait que les
-- transitions VERS un statut de modération), prouve que l'attaque du point 6
-- réussirait alors, puis annule. Un test qui passe ne prouve rien s'il
-- serait passé avant le correctif.
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/moderation_gate_test.sql
-- =========================================================================

begin;

insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'a1000000-0000-0000-0000-0000000000a1',
   'authenticated', 'authenticated', 'mg_artist@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"mg_artist"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'a2000000-0000-0000-0000-0000000000a2',
   'authenticated', 'authenticated', 'mg_third@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"mg_third"}'::jsonb);

update public.profiles set role = 'artist' where id = 'a1000000-0000-0000-0000-0000000000a1';

-- ---------------------------------------------------------------------------
-- 1) Insertion en 'published' -> 42501.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

do $$
begin
  begin
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes, status)
    values (
      'a1000000-0000-0000-0000-0000000000a1', 'Tentative published direct',
      'a1000000-0000-0000-0000-0000000000a1/direct.mp4', 60, 1000000, 'published'
    );
    raise exception 'ÉCHEC : insertion directe en published aurait dû lever 42501.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : insertion en published bloquée (42501).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2) Insertion en 'pending_moderation' -> 42501.
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    insert into public.videos (artist_id, title, video_path, duration_seconds, size_bytes, status)
    values (
      'a1000000-0000-0000-0000-0000000000a1', 'Tentative pending_moderation direct',
      'a1000000-0000-0000-0000-0000000000a1/pm.mp4', 60, 1000000, 'pending_moderation'
    );
    raise exception 'ÉCHEC : insertion directe en pending_moderation aurait dû lever 42501.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : insertion en pending_moderation bloquée (42501).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Insertion en 'processing' -> succès, published_at NULL.
-- ---------------------------------------------------------------------------
do $$
declare
  v_status       public.video_status;
  v_published_at timestamptz;
begin
  insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes, status)
  values (
    'aa100000-0000-0000-0000-0000000000aa',
    'a1000000-0000-0000-0000-0000000000a1', 'Clip en cours de traitement',
    'a1000000-0000-0000-0000-0000000000a1/processing.mp4', 60, 1000000, 'processing'
  )
  returning status, published_at into v_status, v_published_at;

  if v_status <> 'processing' or v_published_at is not null then
    raise exception 'ÉCHEC : statut ou published_at inattendu (status=%, published_at=%).', v_status, v_published_at;
  end if;
  raise notice 'SUCCES : insertion en processing acceptée, published_at NULL.';
end $$;

-- ---------------------------------------------------------------------------
-- 4) Le clip processing est invisible d'un tiers authentifié et d'anon.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);

do $$
declare
  n integer;
begin
  select count(*) into n from public.videos where id = 'aa100000-0000-0000-0000-0000000000aa';
  if n <> 0 then
    raise exception 'ÉCHEC : un tiers authentifié voit le clip processing (% ligne(s)).', n;
  end if;
  raise notice 'SUCCES : clip processing invisible d''un tiers authentifié.';
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  n integer;
begin
  select count(*) into n from public.videos where id = 'aa100000-0000-0000-0000-0000000000aa';
  if n <> 0 then
    raise exception 'ÉCHEC : anon voit le clip processing (% ligne(s)).', n;
  end if;
  raise notice 'SUCCES : clip processing invisible d''anon.';
end $$;

-- ---------------------------------------------------------------------------
-- 5) L'artiste tente de publier lui-même SON clip processing -> 42501.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

do $$
begin
  begin
    update public.videos set status = 'published'
     where id = 'aa100000-0000-0000-0000-0000000000aa';
    raise exception 'ÉCHEC : l''artiste a pu publier lui-même son clip processing.';
  exception
    when insufficient_privilege then
      raise notice 'SUCCES : auto-publication bloquée (42501).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 6) LE CAS QUI COMPTE LE PLUS : un clip `rejected` ne peut pas être repassé
--    en `published` par son propre artiste.
-- ---------------------------------------------------------------------------
-- Rejet simulé par moderate-video (service_role) : rôle postgres, exempté.
reset role;
update public.videos
   set status = 'rejected',
       moderation_result = '{"reason":"contenu non conforme"}'::jsonb
 where id = 'aa100000-0000-0000-0000-0000000000aa';

reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

do $$
begin
  begin
    update public.videos set status = 'published'
     where id = 'aa100000-0000-0000-0000-0000000000aa';
    raise exception
      'ÉCHEC CRITIQUE : l''artiste a pu annuler lui-même le rejet de son clip '
      '(published_at/status auto-décidés) -- c''est exactement la faille que '
      '20260727010400_moderation_gate.sql devait fermer.';
  exception
    when insufficient_privilege then
      raise notice
        'SUCCES : un artiste sanctionné ne peut pas repasser son clip rejected '
        'en published lui-même (42501).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 7) L'artiste ne peut pas réécrire moderation_result (restauré par le
--    trigger).
-- ---------------------------------------------------------------------------
do $$
declare
  v_result jsonb;
begin
  update public.videos
     set moderation_result = '{"reason":"je me blanchis moi-même"}'::jsonb
   where id = 'aa100000-0000-0000-0000-0000000000aa'
  returning moderation_result into v_result;

  if v_result ->> 'reason' <> 'contenu non conforme' then
    raise exception
      'ÉCHEC : moderation_result a été réécrit par le client (obtenu %).', v_result;
  end if;
  raise notice 'SUCCES : moderation_result restauré par le trigger, non réécrit par le client.';
end $$;

-- ---------------------------------------------------------------------------
-- 8) CONTRE-ÉPREUVE POSITIVE : l'artiste peut TOUJOURS modifier titre,
--    description, miniature et genre de son clip -- le verrou ne bloque QUE
--    le statut/les compteurs/moderation_result.
-- ---------------------------------------------------------------------------
do $$
declare
  v_title          text;
  v_description    text;
  v_thumbnail_path text;
  v_genre_id       integer;
  v_new_genre_id   integer;
begin
  select id into v_new_genre_id from public.genres where slug = 'jazz';

  update public.videos
     set title = 'Titre modifié depuis le Studio',
         description = 'Nouvelle description légitime',
         thumbnail_path = 'a1000000-0000-0000-0000-0000000000a1/nouvelle-miniature.jpg',
         genre_id = v_new_genre_id
   where id = 'aa100000-0000-0000-0000-0000000000aa'
  returning title, description, thumbnail_path, genre_id
    into v_title, v_description, v_thumbnail_path, v_genre_id;

  if v_title <> 'Titre modifié depuis le Studio'
     or v_description <> 'Nouvelle description légitime'
     or v_thumbnail_path <> 'a1000000-0000-0000-0000-0000000000a1/nouvelle-miniature.jpg'
     or v_genre_id is distinct from v_new_genre_id then
    raise exception
      'ÉCHEC : la modification légitime (titre/description/miniature/genre) a '
      'été bloquée -- le verrou de modération a cassé le Studio.';
  end if;
  raise notice
    'SUCCES : titre/description/miniature/genre restent modifiables par '
    'l''artiste -- le verrou ne bloque que le statut et les champs de modération.';
end $$;

-- ---------------------------------------------------------------------------
-- 9) En reset role (rôle exempté, ce que fait moderate-video), la transition
--    processing -> published fonctionne. On repart d'un clip neuf (celui
--    testé plus haut est désormais 'rejected', on ne le republie pas pour ne
--    pas contredire le point 6 dans les faits).
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes, status)
values (
  'aa200000-0000-0000-0000-0000000000aa',
  'a1000000-0000-0000-0000-0000000000a1', 'Clip à publier par moderate-video',
  'a1000000-0000-0000-0000-0000000000a1/to-publish.mp4', 60, 1000000, 'processing'
);

reset role;

do $$
declare
  v_status       public.video_status;
  v_published_at timestamptz;
begin
  update public.videos
     set status = 'published', published_at = now()
   where id = 'aa200000-0000-0000-0000-0000000000aa'
  returning status, published_at into v_status, v_published_at;

  if v_status <> 'published' or v_published_at is null then
    raise exception
      'ÉCHEC : la transition processing -> published par le rôle exempté '
      '(service_role/postgres) a échoué (status=%, published_at=%).', v_status, v_published_at;
  end if;
  raise notice
    'SUCCES : processing -> published fonctionne pour le rôle exempté '
    '(ce que fait moderate-video en service_role).';
end $$;

-- =========================================================================
-- CONTRE-ÉPREUVE : rétablit l'ANCIENNE version du trigger (Phase 3, celle de
-- 20260726010000_social.sql), qui n'autorisait QUE les transitions VERS un
-- statut de modération à être bloquées -- pas les transitions FUYANT un
-- statut de modération. Prouve que l'attaque du point 6 aurait alors réussi.
-- =========================================================================
reset role;
savepoint counter_proof;

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
    new.view_count := 0;
    new.like_count := 0;
    new.comment_count := 0;

    if new.status not in ('processing', 'published') then
      raise exception
        'Statut % non autorisé à la création d''une vidéo.', new.status
        using errcode = '42501';
    end if;

    if new.status = 'published' then
      new.published_at := now();
    else
      new.published_at := null;
    end if;

    return new;
  end if;

  new.view_count := old.view_count;
  new.like_count := old.like_count;
  new.comment_count := old.comment_count;

  if new.status is distinct from old.status
     and new.status in ('pending_moderation', 'rejected', 'removed') then
    raise exception
      'Transition vers le statut % réservée à la modération.', new.status
      using errcode = '42501';
  end if;

  if new.status = 'published' and old.status is distinct from 'published' then
    new.published_at := now();
  end if;

  return new;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

do $$
declare
  v_status public.video_status;
begin
  -- Le clip aa100000... est toujours 'rejected' à ce stade (point 6). Avec
  -- l'ancien trigger, rien ne bloque plus la transition rejected -> published
  -- (elle ne figure QUE dans la liste des transitions VERS un statut de
  -- modération, pas depuis un statut de modération).
  update public.videos set status = 'published'
   where id = 'aa100000-0000-0000-0000-0000000000aa'
  returning status into v_status;

  if v_status <> 'published' then
    raise exception
      'ÉCHEC CONTRE-ÉPREUVE : avec l''ancien trigger, l''auto-republication '
      'aurait dû réussir (statut obtenu %) -- le test principal ne prouverait '
      'donc rien.', v_status;
  end if;
  raise notice
    'SUCCES CONTRE-ÉPREUVE : avec l''ancien trigger (Phase 3), l''artiste '
    'PEUT effectivement republier lui-même son clip rejeté -- ce qui prouve '
    'que le blocage observé au point 6 vient bien du nouveau trigger '
    '(20260727010400_moderation_gate.sql), pas d''un artefact du test.';
end $$;

reset role;
rollback to savepoint counter_proof;

reset role;
rollback;
