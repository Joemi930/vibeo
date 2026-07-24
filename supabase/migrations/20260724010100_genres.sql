-- Migration : table de référence des genres musicaux + RLS.
-- Lecture publique ; écriture réservée à service_role (aucune politique client).

create table public.genres (
  id         integer generated always as identity primary key,
  name       text not null,
  slug       text not null unique
);

comment on table public.genres is
  'Genres musicaux (données de référence). Lecture publique, écriture service_role uniquement.';

alter table public.genres enable row level security;

-- Lecture publique (données de référence non sensibles) pour anon + authenticated.
create policy genres_select_all
  on public.genres
  for select
  to anon, authenticated
  using (true);

-- Pas de politique insert/update/delete : modifications via service_role/admin
-- (à ajouter dans une phase ultérieure avec l''administration).

-- Droits d''accès table (lecture seule) pour anon + authenticated. Sans ce
-- GRANT, PostgREST renvoie « permission denied » malgré la politique SELECT.
grant select on public.genres to anon, authenticated;
