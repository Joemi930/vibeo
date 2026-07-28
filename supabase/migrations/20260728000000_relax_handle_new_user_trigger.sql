-- =============================================================================
-- Phase 7 — Assouplit le trigger handle_new_user pour accepter tout username
--           >= 4 caractères (cohérent avec le CHECK relaxé en 20260727010600).
--
-- La migration originale 20260724010000 utilisait un regex `^[a-z0-9_]{3,30}$`
-- qui rejetait les majuscules, les accents, et tout caractère non-ASCII. Depuis
-- la Phase 7, le CHECK sur profiles.username est passé à `char_length >= 4` :
-- le trigger doit suivre la même règle.
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta_username text;
  final_username text;
begin
  meta_username := new.raw_user_meta_data ->> 'username';

  -- Utilise le username fourni s'il respecte la longueur minimale (>= 4),
  -- sinon un fallback unique. Cohérent avec le CHECK sur profiles.username.
  if meta_username is not null and char_length(meta_username) >= 4 then
    final_username := meta_username;
  else
    final_username := 'user_' || substr(replace(new.id::text, '-', ''), 1, 12);
  end if;

  insert into public.profiles (id, username, display_name, role)
  values (
    new.id,
    final_username,
    new.raw_user_meta_data ->> 'display_name',
    'listener'
  );

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Crée automatiquement un profil à l''inscription. Le username fourni est '
  'accepté s''il fait >= 4 caractères (règle assouplie Phase 7).';
