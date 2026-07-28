-- Migration : profils utilisateurs (profiles) + rôle + RLS + trigger.
-- Phase 1 (Fondations + Auth). RLS activée dès la création, politiques nommées.

-- ---------------------------------------------------------------------------
-- Enum des rôles utilisateurs.
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('listener', 'artist', 'admin');

-- ---------------------------------------------------------------------------
-- Table profiles : une ligne par utilisateur (lié à auth.users).
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text not null unique
               check (username ~ '^[a-z0-9_]{3,30}$'),
  display_name text check (char_length(display_name) <= 50),
  avatar_url   text,
  bio          text check (char_length(bio) <= 500),
  role         public.user_role not null default 'listener',
  created_at   timestamptz not null default now()
);

comment on table public.profiles is
  'Profil public d''un utilisateur Vibeo. RLS : accès à sa propre ligne uniquement en P1.';

-- Index sur username (filtre/recherche futurs). L''unicité crée déjà un index,
-- mais on documente l''intention ; pas de doublon nécessaire.

-- ---------------------------------------------------------------------------
-- Sécurité : empêcher un utilisateur de définir/modifier son propre rôle
-- (anti-escalade de privilège), à l''INSERT comme à l''UPDATE. Seuls
-- service_role / rôles d''administration de la base peuvent toucher `role`.
-- Défense en profondeur : on ne dépend PAS de la seule contrainte PK pour
-- bloquer un INSERT client tentant `role = 'admin'`.
-- ---------------------------------------------------------------------------
create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
as $$
begin
  -- service_role / rôles d''administration (dont le SECURITY DEFINER
  -- handle_new_user qui s''exécute en tant que postgres) : aucune restriction.
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  -- INSERT côté client : on force systématiquement le rôle par défaut.
  if tg_op = 'INSERT' then
    new.role := 'listener';
    return new;
  end if;

  -- UPDATE côté client : interdiction de changer son propre rôle.
  if new.role is distinct from old.role then
    raise exception 'Modification du rôle interdite (%).', current_user
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger profiles_prevent_role_escalation
  before insert or update on public.profiles
  for each row
  execute function public.prevent_role_escalation();

-- ---------------------------------------------------------------------------
-- Création automatique du profil à l''inscription (trigger sur auth.users).
-- SECURITY DEFINER + search_path vide (référence qualifiée en public.).
-- ---------------------------------------------------------------------------
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

  -- Utilise le username fourni s''il respecte la longueur minimale (>= 4),
  -- sinon un fallback unique. La règle a été assouplie en Phase 7 : toute
  -- chaîne >= 4 caractères est acceptée (le CHECK sur profiles.username aussi).
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

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RLS : chaque utilisateur n''accède qu''à SA propre ligne (strict en P1).
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy profiles_select_own
  on public.profiles
  for select
  to authenticated
  using (auth.uid() = id);

create policy profiles_insert_own
  on public.profiles
  for insert
  to authenticated
  with check (auth.uid() = id);

create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Aucune politique DELETE : suppression interdite côté client.

-- ---------------------------------------------------------------------------
-- Droits d''accès table pour le rôle applicatif `authenticated`. Les politiques
-- RLS ci-dessus filtrent les LIGNES ; ce GRANT autorise l''ACCÈS à la table.
-- Indispensable : les nouvelles tables ne sont plus exposées automatiquement
-- aux rôles anon/authenticated (sinon PostgREST renvoie « permission denied »).
-- Pas de DELETE (aucune politique de suppression), pas d''accès anon (profils
-- privés en P1).
-- ---------------------------------------------------------------------------
grant select, insert, update on public.profiles to authenticated;
