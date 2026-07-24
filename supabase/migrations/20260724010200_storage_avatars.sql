-- Migration : bucket Storage privé `avatars` + politiques RLS.
-- Règle CLAUDE.md n°4 : buckets privés, accès par URL signée uniquement.
-- Chaque utilisateur ne gère que les objets de SON dossier (premier segment de
-- chemin = son auth.uid()), ce qui lui permet aussi de générer une URL signée
-- pour son propre avatar.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  false,
  5242880, -- 5 Mo
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do nothing;

-- SELECT (nécessaire pour createSignedUrl) : uniquement ses propres objets.
create policy avatars_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- INSERT : dépôt uniquement dans son dossier.
create policy avatars_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- UPDATE (upsert) : uniquement ses propres objets.
create policy avatars_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- DELETE : uniquement ses propres objets.
create policy avatars_delete_own
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
