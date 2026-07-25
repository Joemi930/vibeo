-- =========================================================================
-- Test RLS — tables sociales (likes, comments, subscriptions, playlists,
-- playlist_items, reports) + politique view_events_select_own.
-- Démontre :
--   1. Double like du même utilisateur -> le 2nd échoue (unique_violation),
--      like_count reste à 1.
--   2. Unlike puis relike -> compteur cohérent (1, 0, 1).
--   3. A commente ; B ne peut pas supprimer le commentaire de A ; A peut ;
--      comment_count suit.
--   4. L'artiste propriétaire du clip ne peut pas non plus supprimer le
--      commentaire de A.
--   5. Playlist privée de A : invisible pour B (playlists + playlist_items).
--   6. Playlist rendue publique -> visible en lecture pour B, mais B ne peut
--      pas y ajouter d'élément.
--   7. Abonnement : subscriber_count suit ; pas d'auto-abonnement.
--   8. Un signalement inséré par un non-admin n'est pas relisible par lui.
--   9. Le client ne peut pas écrire like_count / comment_count / item_count /
--      subscriber_count.
--  10. view_events : A voit ses propres vues, pas celles de B.
--  11. (bonus) Limite de 30 commentaires/heure.
--  12. (bonus) Limite de 20 signalements/jour.
--  13. B ne voit ni les likes ni les abonnements de A (graphe social
--      prive), mais like_count/subscriber_count restent justes.
--  14. Un signalement survit a la suppression de sa cible : target_kind
--      et target_author_id conservent la trace de moderation.
--  15. Le client ne peut ecrire ni target_kind ni target_author_id.
--  16. reorder_playlist : proprietaire seulement, ordre reecrit,
--      tableau incomplet rejete.
--
-- Exécution (stack locale démarrée) :
--   supabase db reset && \
--   psql postgresql://postgres:postgres@127.0.0.1:55322/postgres \
--        -f supabase/tests/rls_social_test.sql
--
-- Le script s'exécute dans une transaction annulée à la fin (rollback) :
-- il ne laisse aucune donnée derrière lui.
-- =========================================================================

begin;

-- ---------------------------------------------------------------------------
-- Comptes de test.
--   A = 'a0000000-0000-0000-0000-00000000000a' (listener)
--   B = 'b0000000-0000-0000-0000-00000000000b' (listener)
--   C = 'c0000000-0000-0000-0000-00000000000c' (artiste, propriétaire des clips)
--   D = 'd0000000-0000-0000-0000-00000000000d' (admin)
-- ---------------------------------------------------------------------------
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000',
   'a0000000-0000-0000-0000-00000000000a',
   'authenticated', 'authenticated', 'a_social@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"a_listener"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'b0000000-0000-0000-0000-00000000000b',
   'authenticated', 'authenticated', 'b_social@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"b_listener"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'c0000000-0000-0000-0000-00000000000c',
   'authenticated', 'authenticated', 'c_social@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"c_artist"}'::jsonb),
  ('00000000-0000-0000-0000-000000000000',
   'd0000000-0000-0000-0000-00000000000d',
   'authenticated', 'authenticated', 'd_social@test.dev', '',
   now(), now(), '{}'::jsonb, '{"username":"d_admin"}'::jsonb);

update public.profiles set role = 'artist' where id = 'c0000000-0000-0000-0000-00000000000c';
update public.profiles set role = 'admin'  where id = 'd0000000-0000-0000-0000-00000000000d';

-- Deux clips publiés de l'artiste C.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000c","role":"authenticated"}',
  true
);

insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes, status)
values (
  'e0000000-0000-0000-0000-00000000000e',
  'c0000000-0000-0000-0000-00000000000c',
  'Clip social 1',
  'c0000000-0000-0000-0000-00000000000c/clip1.mp4',
  60, 1000000, 'published'
);

insert into public.videos (id, artist_id, title, video_path, duration_seconds, size_bytes, status)
values (
  'e0000000-0000-0000-0000-00000000000f',
  'c0000000-0000-0000-0000-00000000000c',
  'Clip social 2',
  'c0000000-0000-0000-0000-00000000000c/clip2.mp4',
  60, 1000000, 'published'
);

-- ---------------------------------------------------------------------------
-- 1) Double like du même utilisateur -> le 2nd échoue, like_count reste à 1.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  v_like_count bigint;
begin
  insert into public.likes (video_id, user_id)
  values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a');

  select like_count into v_like_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_like_count <> 1 then
    raise exception 'ÉCHEC : like_count attendu à 1 après un like, obtenu %.', v_like_count;
  end if;

  begin
    insert into public.likes (video_id, user_id)
    values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a');
    raise exception 'ÉCHEC : un second like du même utilisateur a été accepté.';
  exception
    when unique_violation then
      raise notice '✅ SUCCÈS : le double like est bloqué par la PK (video_id, user_id).';
  end;

  select like_count into v_like_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_like_count <> 1 then
    raise exception 'ÉCHEC : like_count a changé après le double like rejeté (%).', v_like_count;
  end if;
  raise notice '✅ SUCCÈS : like_count reste à 1 après la tentative de double like.';
end $$;

-- ---------------------------------------------------------------------------
-- 2) Unlike puis relike -> compteur cohérent (1, 0, 1).
-- ---------------------------------------------------------------------------
do $$
declare
  v_like_count bigint;
  v_deleted    int;
begin
  delete from public.likes
   where video_id = 'e0000000-0000-0000-0000-00000000000e'
     and user_id = 'a0000000-0000-0000-0000-00000000000a';
  get diagnostics v_deleted = row_count;

  select like_count into v_like_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_deleted <> 1 or v_like_count <> 0 then
    raise exception 'ÉCHEC : unlike inattendu (deleted=%, like_count=%).', v_deleted, v_like_count;
  end if;

  insert into public.likes (video_id, user_id)
  values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a');

  select like_count into v_like_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_like_count <> 1 then
    raise exception 'ÉCHEC : relike -> like_count attendu à 1, obtenu %.', v_like_count;
  end if;
  raise notice '✅ SUCCÈS : unlike puis relike -> compteur cohérent (1, 0, 1).';
end $$;

-- ---------------------------------------------------------------------------
-- 3) A commente ; B ne peut pas supprimer le commentaire de A ; A peut ;
--    comment_count suit.
-- ---------------------------------------------------------------------------
do $$
declare
  v_comment_id     uuid;
  v_comment_count  bigint;
begin
  insert into public.comments (video_id, author_id, body)
  values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a', 'Premier commentaire de A')
  returning id into v_comment_id;

  select comment_count into v_comment_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_comment_count <> 1 then
    raise exception 'ÉCHEC : comment_count attendu à 1 après insertion, obtenu %.', v_comment_count;
  end if;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
    true
  );

  delete from public.comments where id = v_comment_id;
  if found then
    raise exception 'ÉCHEC : B a pu supprimer le commentaire de A.';
  end if;

  select comment_count into v_comment_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_comment_count <> 1 then
    raise exception 'ÉCHEC : comment_count a changé après la tentative de suppression par B (%).', v_comment_count;
  end if;
  raise notice '✅ SUCCÈS : B ne peut pas supprimer le commentaire de A (comments_delete_own).';

  perform set_config(
    'request.jwt.claims',
    '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
    true
  );

  delete from public.comments where id = v_comment_id;
  if not found then
    raise exception 'ÉCHEC : A n''a pas pu supprimer SON PROPRE commentaire.';
  end if;

  select comment_count into v_comment_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_comment_count <> 0 then
    raise exception 'ÉCHEC : comment_count attendu à 0 après suppression par l''auteur, obtenu %.', v_comment_count;
  end if;
  raise notice '✅ SUCCÈS : A peut supprimer son propre commentaire, comment_count suit (1 -> 0).';
end $$;

-- ---------------------------------------------------------------------------
-- 4) L'artiste propriétaire du clip (C) ne peut pas non plus supprimer le
--    commentaire de A. Critère explicite du cahier des charges.
-- ---------------------------------------------------------------------------
do $$
declare
  v_comment_id    uuid;
  v_comment_count bigint;
begin
  insert into public.comments (video_id, author_id, body)
  values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a', 'Second commentaire de A')
  returning id into v_comment_id;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"c0000000-0000-0000-0000-00000000000c","role":"authenticated"}',
    true
  );

  delete from public.comments where id = v_comment_id;
  if found then
    raise exception 'ÉCHEC : l''artiste propriétaire du clip a pu supprimer le commentaire de A.';
  end if;

  select comment_count into v_comment_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_comment_count <> 1 then
    raise exception 'ÉCHEC : comment_count a changé après la tentative de suppression par l''artiste (%).', v_comment_count;
  end if;
  raise notice '✅ SUCCÈS : l''artiste propriétaire du clip ne peut pas supprimer le commentaire de A.';

  -- Nettoyage : A supprime son propre commentaire pour repartir sur une base
  -- propre (comment_count = 0) avant les tests suivants.
  perform set_config(
    'request.jwt.claims',
    '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
    true
  );
  delete from public.comments where id = v_comment_id;

  select comment_count into v_comment_count from public.videos where id = 'e0000000-0000-0000-0000-00000000000e';
  if v_comment_count <> 0 then
    raise exception 'ÉCHEC : nettoyage -- comment_count attendu à 0, obtenu %.', v_comment_count;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5) Playlist privée de A : invisible pour B (playlists + playlist_items),
--    visible pour A.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  v_item_count int;
begin
  insert into public.playlists (id, owner_id, title, is_public)
  values ('f0000000-0000-0000-0000-00000000000f', 'a0000000-0000-0000-0000-00000000000a', 'Ma playlist privée', false);

  insert into public.playlist_items (playlist_id, video_id, position)
  values ('f0000000-0000-0000-0000-00000000000f', 'e0000000-0000-0000-0000-00000000000e', 0);

  select item_count into v_item_count from public.playlists where id = 'f0000000-0000-0000-0000-00000000000f';
  if v_item_count <> 1 then
    raise exception 'ÉCHEC : item_count attendu à 1, obtenu %.', v_item_count;
  end if;
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

do $$
declare
  n_playlist int;
  n_items    int;
begin
  select count(*) into n_playlist from public.playlists where id = 'f0000000-0000-0000-0000-00000000000f';
  if n_playlist <> 0 then
    raise exception 'ÉCHEC : B voit la playlist privée de A (% ligne(s)).', n_playlist;
  end if;

  select count(*) into n_items from public.playlist_items where playlist_id = 'f0000000-0000-0000-0000-00000000000f';
  if n_items <> 0 then
    raise exception 'ÉCHEC : B voit les items de la playlist privée de A (% ligne(s)).', n_items;
  end if;
  raise notice '✅ SUCCÈS : playlist privée de A invisible pour B (playlists et playlist_items).';
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  n_playlist int;
begin
  select count(*) into n_playlist from public.playlists where id = 'f0000000-0000-0000-0000-00000000000f';
  if n_playlist <> 1 then
    raise exception 'ÉCHEC : A ne voit pas sa propre playlist (% ligne(s)).', n_playlist;
  end if;
  raise notice '✅ SUCCÈS : A voit sa propre playlist privée.';
end $$;

-- ---------------------------------------------------------------------------
-- 6) Playlist passée en is_public -> visible pour B en lecture, mais B ne
--    peut pas y ajouter d'élément.
-- ---------------------------------------------------------------------------
do $$
begin
  update public.playlists set is_public = true where id = 'f0000000-0000-0000-0000-00000000000f';
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

do $$
declare
  n_playlist int;
begin
  select count(*) into n_playlist from public.playlists where id = 'f0000000-0000-0000-0000-00000000000f';
  if n_playlist <> 1 then
    raise exception 'ÉCHEC : B ne voit pas la playlist désormais publique de A (% ligne(s)).', n_playlist;
  end if;
  raise notice '✅ SUCCÈS : playlist publique de A visible pour B en lecture.';

  begin
    insert into public.playlist_items (playlist_id, video_id, position)
    values ('f0000000-0000-0000-0000-00000000000f', 'e0000000-0000-0000-0000-00000000000f', 1);
    raise exception 'ÉCHEC : B a pu ajouter un clip à la playlist publique de A.';
  exception
    when insufficient_privilege then
      raise notice '✅ SUCCÈS : B ne peut pas ajouter d''élément à une playlist qui ne lui appartient pas.';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 7) Abonnement : A s'abonne à C -> subscriber_count de C = 1 ; désabonnement
--    -> 0 ; A ne peut pas s'abonner à lui-même.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  v_subscriber_count bigint;
begin
  insert into public.subscriptions (artist_id, subscriber_id)
  values ('c0000000-0000-0000-0000-00000000000c', 'a0000000-0000-0000-0000-00000000000a');

  select subscriber_count into v_subscriber_count from public.profiles where id = 'c0000000-0000-0000-0000-00000000000c';
  if v_subscriber_count <> 1 then
    raise exception 'ÉCHEC : subscriber_count attendu à 1, obtenu %.', v_subscriber_count;
  end if;

  delete from public.subscriptions
   where artist_id = 'c0000000-0000-0000-0000-00000000000c'
     and subscriber_id = 'a0000000-0000-0000-0000-00000000000a';

  select subscriber_count into v_subscriber_count from public.profiles where id = 'c0000000-0000-0000-0000-00000000000c';
  if v_subscriber_count <> 0 then
    raise exception 'ÉCHEC : subscriber_count attendu à 0 après désabonnement, obtenu %.', v_subscriber_count;
  end if;
  raise notice '✅ SUCCÈS : abonnement/désabonnement -> subscriber_count cohérent (1, 0).';

  begin
    insert into public.subscriptions (artist_id, subscriber_id)
    values ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-00000000000a');
    raise exception 'ÉCHEC : A a pu s''abonner à lui-même.';
  exception
    when check_violation then
      raise notice '✅ SUCCÈS : auto-abonnement bloqué (check artist_id <> subscriber_id).';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 8) reports : un utilisateur non admin insère un signalement puis ne peut
--    pas le relire (0 ligne).
-- ---------------------------------------------------------------------------
do $$
declare
  n int;
begin
  insert into public.reports (reporter_id, video_id, reason)
  values ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000e', 'spam');

  select count(*) into n from public.reports;
  if n <> 0 then
    raise exception 'ÉCHEC : un utilisateur non admin relit % signalement(s).', n;
  end if;
  raise notice '✅ SUCCÈS : un signalement inséré n''est pas relisible par son auteur (select réservé aux admins).';
end $$;

-- Vérification côté admin (D) : il doit bien voir ce signalement.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-00000000000d","role":"authenticated"}',
  true
);

do $$
declare
  n int;
begin
  -- C'est bien le signalement inséré par A juste au-dessus que l'admin doit
  -- voir (D est l'admin qui regarde, pas l'auteur du signalement).
  select count(*) into n from public.reports
   where reporter_id = 'a0000000-0000-0000-0000-00000000000a'
     and video_id = 'e0000000-0000-0000-0000-00000000000e';
  if n <> 1 then
    raise exception 'ÉCHEC : l''admin ne voit pas le signalement (% ligne(s)).', n;
  end if;
  raise notice '✅ SUCCÈS : l''admin voit les signalements (reports_select_admin).';
end $$;

-- ---------------------------------------------------------------------------
-- 9) Le client ne peut pas écrire directement like_count / comment_count /
--    item_count / subscriber_count.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000c","role":"authenticated"}',
  true
);

do $$
declare
  v_like_count    bigint;
  v_comment_count bigint;
begin
  update public.videos
     set like_count = 9999,
         comment_count = 9999
   where id = 'e0000000-0000-0000-0000-00000000000e'
  returning like_count, comment_count into v_like_count, v_comment_count;

  if v_like_count <> 1 or v_comment_count <> 0 then
    raise exception
      'ÉCHEC : le client a pu modifier like_count/comment_count (like=%, comment=%).',
      v_like_count, v_comment_count;
  end if;
  raise notice '✅ SUCCÈS : like_count et comment_count restaurés par videos_guard_client_fields.';
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  v_item_count int;
begin
  update public.playlists
     set item_count = 9999
   where id = 'f0000000-0000-0000-0000-00000000000f'
  returning item_count into v_item_count;

  if v_item_count <> 1 then
    raise exception 'ÉCHEC : le client a pu modifier item_count (obtenu %).', v_item_count;
  end if;
  raise notice '✅ SUCCÈS : item_count restauré par playlists_guard_client_fields.';
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000c","role":"authenticated"}',
  true
);

do $$
declare
  v_subscriber_count bigint;
begin
  update public.profiles
     set subscriber_count = 9999
   where id = 'c0000000-0000-0000-0000-00000000000c'
  returning subscriber_count into v_subscriber_count;

  if v_subscriber_count <> 0 then
    raise exception 'ÉCHEC : le client a pu modifier subscriber_count (obtenu %).', v_subscriber_count;
  end if;
  raise notice '✅ SUCCÈS : subscriber_count restauré par prevent_role_escalation.';
end $$;

-- ---------------------------------------------------------------------------
-- 10) view_events : A voit ses propres vues, pas celles de B.
-- ---------------------------------------------------------------------------
reset role;
insert into public.view_events (video_id, user_id, watched_seconds)
values
  ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a', 15),
  ('e0000000-0000-0000-0000-00000000000e', 'b0000000-0000-0000-0000-00000000000b', 20);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  n_total int;
  n_mine  int;
begin
  select count(*) into n_total from public.view_events;
  select count(*) into n_mine
    from public.view_events
   where user_id = 'a0000000-0000-0000-0000-00000000000a';

  if n_total <> 1 or n_mine <> 1 then
    raise exception
      'ÉCHEC : A voit % vue(s) au total (attendu 1, uniquement les siennes).', n_total;
  end if;
  raise notice '✅ SUCCÈS : A ne voit que ses propres view_events (1 ligne, pas celle de B).';
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

do $$
declare
  n_total int;
begin
  select count(*) into n_total from public.view_events;
  if n_total <> 1 then
    raise exception 'ÉCHEC : B voit % vue(s) au total (attendu 1, uniquement la sienne).', n_total;
  end if;
  raise notice '✅ SUCCÈS : B ne voit que sa propre view_events (1 ligne, pas celle de A).';
end $$;

-- ---------------------------------------------------------------------------
-- 11) (bonus) Limite de 30 commentaires/heure.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  i int;
  blocked boolean := false;
begin
  for i in 1..40 loop
    begin
      insert into public.comments (video_id, author_id, body)
      values ('e0000000-0000-0000-0000-00000000000e', 'a0000000-0000-0000-0000-00000000000a', 'Commentaire quota ' || i);
    exception
      when sqlstate '54000' then
        blocked := true;
        exit;
    end;
  end loop;

  if not blocked then
    raise exception 'ÉCHEC : la limite de 30 commentaires/heure n''a pas été appliquée après 40 tentatives.';
  end if;
  raise notice '✅ SUCCÈS : limite de 30 commentaires/heure appliquée (errcode 54000).';
end $$;

-- ---------------------------------------------------------------------------
-- 12) (bonus) Limite de 20 signalements/jour.
-- Nécessite des cibles distinctes (unicité reporter+cible) : B publie 25
-- commentaires, A les signale un par un jusqu'à blocage.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

do $$
declare
  i int;
begin
  for i in 1..25 loop
    insert into public.comments (video_id, author_id, body)
    values ('e0000000-0000-0000-0000-00000000000e', 'b0000000-0000-0000-0000-00000000000b', 'Cible signalement ' || i);
  end loop;
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  rec record;
  blocked boolean := false;
begin
  for rec in
    select id from public.comments
     where author_id = 'b0000000-0000-0000-0000-00000000000b'
       and body like 'Cible signalement%'
     order by created_at
  loop
    begin
      insert into public.reports (reporter_id, comment_id, reason)
      values ('a0000000-0000-0000-0000-00000000000a', rec.id, 'spam');
    exception
      when sqlstate '54000' then
        blocked := true;
        exit;
    end;
  end loop;

  if not blocked then
    raise exception 'ÉCHEC : la limite de 20 signalements/jour n''a pas été appliquée après 25 tentatives.';
  end if;
  raise notice '✅ SUCCÈS : limite de 20 signalements/jour appliquée (errcode 54000).';
end $$;

-- ---------------------------------------------------------------------------
-- 13) Confidentialite du graphe social : B ne voit ni les likes ni les
--     abonnements de A, alors que les compteurs agreges restent justes.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

insert into public.likes (video_id, user_id)
values ('e0000000-0000-0000-0000-00000000000f', 'a0000000-0000-0000-0000-00000000000a')
on conflict do nothing;

insert into public.subscriptions (artist_id, subscriber_id)
values ('c0000000-0000-0000-0000-00000000000c', 'a0000000-0000-0000-0000-00000000000a')
on conflict do nothing;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

do $$
declare
  n_likes int;
  n_subs  int;
  v_likes bigint;
  v_subs  bigint;
begin
  select count(*) into n_likes
    from public.likes
   where user_id = 'a0000000-0000-0000-0000-00000000000a';
  if n_likes <> 0 then
    raise exception 'ECHEC : B voit les likes de A (% ligne(s)).', n_likes;
  end if;

  select count(*) into n_subs
    from public.subscriptions
   where subscriber_id = 'a0000000-0000-0000-0000-00000000000a';
  if n_subs <> 0 then
    raise exception 'ECHEC : B voit les abonnements de A (% ligne(s)).', n_subs;
  end if;

  -- Les totaux, eux, restent publics : ce sont les colonnes compteur.
  select like_count into v_likes
    from public.videos where id = 'e0000000-0000-0000-0000-00000000000f';
  select subscriber_count into v_subs
    from public.profiles where id = 'c0000000-0000-0000-0000-00000000000c';
  if v_likes < 1 then
    raise exception 'ECHEC : like_count devrait valoir au moins 1, obtenu %.', v_likes;
  end if;
  if v_subs < 1 then
    raise exception 'ECHEC : subscriber_count devrait valoir au moins 1, obtenu %.', v_subs;
  end if;

  raise notice 'SUCCES : likes et abonnements de A invisibles pour B, compteurs justes.';
end $$;

-- ---------------------------------------------------------------------------
-- 14) Un signalement survit a la suppression de sa cible.
--     C'est le correctif de la faille trouvee a l'audit : avec ON DELETE
--     CASCADE, l'auteur d'un contenu signale effacait la preuve en supprimant
--     son propre contenu (les cascades FK s'executent hors RLS).
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

insert into public.comments (id, video_id, author_id, body)
values (
  'aa000000-0000-0000-0000-0000000000aa',
  'e0000000-0000-0000-0000-00000000000e',
  'b0000000-0000-0000-0000-00000000000b',
  'Commentaire qui sera signale puis supprime par son auteur'
);

-- C signale (et non A, dont le quota de 20 signalements/jour a ete
-- volontairement epuise par le test 12 dans la meme transaction).
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"c0000000-0000-0000-0000-00000000000c","role":"authenticated"}',
  true
);

insert into public.reports (reporter_id, comment_id, reason)
values ('c0000000-0000-0000-0000-00000000000c', 'aa000000-0000-0000-0000-0000000000aa', 'hate_speech');

-- B, auteur du commentaire signale, le supprime pour effacer la trace.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

delete from public.comments where id = 'aa000000-0000-0000-0000-0000000000aa';

-- L'admin doit toujours retrouver le signalement, avec son contexte.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-00000000000d","role":"authenticated"}',
  true
);

do $$
declare
  v_comment_id uuid;
  v_kind       public.report_target;
  v_author     uuid;
  n_found      int;
begin
  select count(*) into n_found
    from public.reports r
   where r.reporter_id = 'c0000000-0000-0000-0000-00000000000c'
     and r.reason = 'hate_speech';

  if n_found = 0 then
    raise exception 'ECHEC : le signalement a disparu avec sa cible (cascade FK).';
  end if;

  select r.comment_id, r.target_kind, r.target_author_id
    into v_comment_id, v_kind, v_author
    from public.reports r
   where r.reporter_id = 'c0000000-0000-0000-0000-00000000000c'
     and r.reason = 'hate_speech'
   limit 1;

  if v_comment_id is not null then
    raise exception 'ECHEC : comment_id devrait etre NULL apres suppression, obtenu %.', v_comment_id;
  end if;
  if v_kind <> 'comment' then
    raise exception 'ECHEC : target_kind attendu "comment", obtenu %.', v_kind;
  end if;
  if v_author <> 'b0000000-0000-0000-0000-00000000000b' then
    raise exception 'ECHEC : target_author_id attendu B, obtenu %.', v_author;
  end if;

  raise notice 'SUCCES : signalement conserve apres suppression de la cible, auteur incrimine trace.';
end $$;

-- ---------------------------------------------------------------------------
-- 15) Le client ne peut ecrire ni target_kind ni target_author_id : ils sont
--     deduits en base par le trigger, pas repris de ce qu'il envoie.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-00000000000d","role":"authenticated"}',
  true
);

insert into public.reports
  (reporter_id, video_id, reason, target_kind, target_author_id)
values
  ('d0000000-0000-0000-0000-00000000000d',
   'e0000000-0000-0000-0000-00000000000e',
   'spam',
   'comment',                                    -- mensonge du client
   'd0000000-0000-0000-0000-00000000000d');      -- mensonge du client

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d0000000-0000-0000-0000-00000000000d","role":"authenticated"}',
  true
);

do $$
declare
  v_kind   public.report_target;
  v_author uuid;
begin
  select target_kind, target_author_id into v_kind, v_author
    from public.reports
   where reporter_id = 'd0000000-0000-0000-0000-00000000000d'
     and video_id = 'e0000000-0000-0000-0000-00000000000e';

  if v_kind <> 'video' then
    raise exception 'ECHEC : target_kind impose par le client (% au lieu de "video").', v_kind;
  end if;
  if v_author <> 'c0000000-0000-0000-0000-00000000000c' then
    raise exception 'ECHEC : target_author_id impose par le client (% au lieu de C).', v_author;
  end if;

  raise notice 'SUCCES : target_kind et target_author_id deduits en base, pas du client.';
end $$;

-- ---------------------------------------------------------------------------
-- 16) reorder_playlist : proprietaire seulement, ordre reecrit, tableau
--     incomplet rejete.
-- ---------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a0000000-0000-0000-0000-00000000000a","role":"authenticated"}',
  true
);

do $$
declare
  v_playlist uuid := '1a000000-0000-0000-0000-0000000000a1';
  v_first    uuid;
  v_rejected boolean := false;
begin
  insert into public.playlists (id, owner_id, title)
  values (v_playlist, 'a0000000-0000-0000-0000-00000000000a', 'Playlist a reordonner');

  insert into public.playlist_items (playlist_id, video_id, position) values
    (v_playlist, 'e0000000-0000-0000-0000-00000000000e', 0),
    (v_playlist, 'e0000000-0000-0000-0000-00000000000f', 1);

  -- Inversion de l'ordre.
  perform public.reorder_playlist(
    v_playlist,
    array['e0000000-0000-0000-0000-00000000000f',
          'e0000000-0000-0000-0000-00000000000e']::uuid[]
  );

  select video_id into v_first
    from public.playlist_items
   where playlist_id = v_playlist
   order by position
   limit 1;

  if v_first <> 'e0000000-0000-0000-0000-00000000000f' then
    raise exception 'ECHEC : reordonnancement sans effet, premier clip = %.', v_first;
  end if;

  -- Tableau incomplet : doit etre rejete.
  begin
    perform public.reorder_playlist(
      v_playlist,
      array['e0000000-0000-0000-0000-00000000000e']::uuid[]
    );
  exception
    when others then
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'ECHEC : un tableau incomplet a ete accepte par reorder_playlist.';
  end if;

  raise notice 'SUCCES : reorder_playlist reecrit l ordre et rejette un tableau incomplet.';
end $$;

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"b0000000-0000-0000-0000-00000000000b","role":"authenticated"}',
  true
);

do $$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.reorder_playlist(
      '1a000000-0000-0000-0000-0000000000a1',
      array['e0000000-0000-0000-0000-00000000000e',
            'e0000000-0000-0000-0000-00000000000f']::uuid[]
    );
  exception
    when others then
      v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'ECHEC : B a pu reordonner la playlist de A.';
  end if;
  raise notice 'SUCCES : reorder_playlist refuse un appelant non proprietaire.';
end $$;

reset role;
rollback;
