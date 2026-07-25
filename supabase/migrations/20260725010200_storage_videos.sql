-- Migration : buckets Storage privés `videos` et `thumbnails` + politiques RLS.
-- Règle CLAUDE.md n°4 : buckets privés, accès par URL signée uniquement.
-- Écriture : chaque artiste ne gère que les objets de SON dossier (premier
-- segment de chemin = son auth.uid()), même patron que `avatars`.
-- Lecture : le propriétaire, un admin, OU tout le monde (anon inclus) si
-- l'objet est rattaché à une vidéo `published` -- les buckets restent privés
-- (public = false), seule une URL signée fonctionne réellement ; une URL
-- brute doit renvoyer 400, c'est un critère de réussite explicite de la
-- Phase 2 (voir docs/ARCHITECTURE.md §2 "Stratégie vidéo à 0 €").

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'videos',
  'videos',
  false,
  62914560, -- 60 Mo
  array['video/mp4', 'video/quicktime']
)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'thumbnails',
  'thumbnails',
  false,
  2097152, -- 2 Mo
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Écriture (insert/update/delete) : uniquement dans son propre dossier, sur
-- les deux buckets.
-- ---------------------------------------------------------------------------
create policy videos_storage_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id in ('videos', 'thumbnails')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy videos_storage_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id in ('videos', 'thumbnails')
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id in ('videos', 'thumbnails')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy videos_storage_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id in ('videos', 'thumbnails')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- Lecture (nécessaire pour createSignedUrl) : trois politiques permissives,
-- combinées par OR par Postgres.
-- ---------------------------------------------------------------------------
-- 1) Le propriétaire de l'objet (avant même publication -- prévisualisation
--    dans le Studio artiste).
create policy videos_storage_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id in ('videos', 'thumbnails')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 2) Un admin (modération, Phase 4).
create policy videos_storage_select_admin
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id in ('videos', 'thumbnails')
    and public.is_admin()
  );

-- 3) Tout le monde (anon inclus) si l'objet est rattaché à une vidéo publiée.
create policy videos_storage_select_published
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id in ('videos', 'thumbnails')
    and exists (
      select 1
      from public.videos v
      where (v.video_path = storage.objects.name or v.thumbnail_path = storage.objects.name)
        and v.status = 'published'
    )
  );
