-- =============================================================================
-- Phase 7 — Assouplissement du nom d'utilisateur.
--
-- Le regex `^[a-z0-9_]{3,30}$` (minuscules uniquement) est remplacé par une
-- simple vérification de longueur minimale (4 caractères). L'unicité est déjà
-- garantie par la contrainte UNIQUE sur la colonne.
-- =============================================================================

-- 1. Contrainte CHECK de `profiles.username`.
alter table public.profiles
  drop constraint if exists profiles_username_check;

alter table public.profiles
  add constraint profiles_username_check
  check (char_length(username) >= 4);

-- 2. Trigger `handle_new_user` : ``create or replace`` de la fonction entière
--    (le corps est identique à l'original, seul le test du regex change).
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

  -- Phase 7 : simple longueur minimale de 4, plus de regex.
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
