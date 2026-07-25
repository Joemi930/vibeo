-- Migration : lecture publique des profils + helpers de rôle + préparation
-- recherche (Phase 3). Phase 2 (Vidéo) : afficher le nom d'un artiste sous
-- une vidéo publique et sous un commentaire nécessite que N'IMPORTE QUI
-- (y compris anon) puisse lire les profils.

-- ---------------------------------------------------------------------------
-- profiles : la politique stricte de la Phase 1 (chacun ne voit que SA ligne)
-- est remplacée par une lecture publique. Ce n'est PAS une fuite de données :
-- la table `profiles` ne contient que des informations déjà publiques par
-- nature (username, display_name, avatar_url, bio, role, compteurs). Les
-- données sensibles (email, téléphone, mot de passe) vivent dans `auth.users`,
-- jamais exposée via PostgREST.
-- ---------------------------------------------------------------------------
drop policy profiles_select_own on public.profiles;

create policy profiles_select_public
  on public.profiles
  for select
  to anon, authenticated
  using (true);

-- Le GRANT existant (Phase 1) ne couvrait que `authenticated` ; on ajoute
-- `anon` pour que la lecture publique fonctionne réellement via PostgREST.
grant select on public.profiles to anon;

-- ---------------------------------------------------------------------------
-- avatars (storage) : même raisonnement, un avatar accompagne un profil
-- désormais public. Remplace `avatars_select_own` par une lecture ouverte
-- à tout le bucket `avatars`. Insert/update/delete restent réservés au
-- propriétaire (non modifiés ici).
-- ---------------------------------------------------------------------------
drop policy avatars_select_own on storage.objects;

create policy avatars_select_all
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'avatars');

-- ---------------------------------------------------------------------------
-- Helpers de rôle, appelables depuis les politiques RLS des tables à venir
-- (videos, etc.). SECURITY DEFINER + search_path verrouillé, noms qualifiés.
-- STABLE : pas d'écriture, résultat cohérent au sein d'une même requête.
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  );
$$;

comment on function public.is_admin() is
  'Vrai si l''utilisateur courant (auth.uid()) est admin. Utilisable dans les politiques RLS.';

create or replace function public.is_artist(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and p.role = 'artist'
  );
$$;

comment on function public.is_artist(uuid) is
  'Vrai si p_user_id a le rôle artist. Utilisable dans les politiques RLS.';

-- Ce ne sont pas des fonctions trigger : elles doivent rester appelables via
-- /rpc par les rôles applicatifs (contrairement à handle_new_user /
-- prevent_role_escalation). On révoque uniquement le rôle `public` (défaut
-- Postgres trop permissif), puis on ré-accorde explicitement.
revoke execute on function public.is_admin() from public;
revoke execute on function public.is_artist(uuid) from public;

-- Moindre privilège : aucune politique `to anon` n'utilise ces helpers, un
-- visiteur non connecté n'a donc aucune raison de pouvoir les appeler.
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_artist(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Compteur d'abonnés, alimenté par trigger en Phase 3 (table `subscriptions`
-- pas encore créée). Colonne ajoutée dès maintenant pour éviter une migration
-- ALTER supplémentaire lors de l'implémentation des abonnements.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column subscriber_count bigint not null default 0;

-- `profiles_update_own` autorise un utilisateur à modifier SA ligne, ce qui
-- inclurait ce nouveau compteur : on étend donc le garde-fou de la Phase 1
-- pour qu'il protège `subscriber_count` comme il protège déjà `role`. Un
-- compteur n'est jamais écrit par le client (règle CLAUDE.md n°6) — seul le
-- trigger d'abonnement (Phase 3), en SECURITY DEFINER, y touchera.
create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- service_role / rôles d'administration (dont le SECURITY DEFINER
  -- handle_new_user qui s'exécute en tant que postgres) : aucune restriction.
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  -- INSERT côté client : on force systématiquement les valeurs par défaut.
  if tg_op = 'INSERT' then
    new.role := 'listener';
    new.subscriber_count := 0;
    return new;
  end if;

  -- UPDATE côté client : ni le rôle ni les compteurs ne sont modifiables.
  if new.role is distinct from old.role then
    raise exception 'Modification du rôle interdite (%).', current_user
      using errcode = '42501';
  end if;

  new.subscriber_count := old.subscriber_count;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Recherche floue (Phase 3) : extension pg_trgm + index trigram sur les
-- colonnes texte les plus recherchées (nom d'utilisateur, nom d'affichage).
-- Installée dans le schéma `extensions` (convention Supabase), déjà inclus
-- dans le search_path PostgREST (voir supabase/config.toml).
-- ---------------------------------------------------------------------------
create extension if not exists pg_trgm with schema extensions;

create index profiles_username_trgm_idx
  on public.profiles
  using gin (username extensions.gin_trgm_ops);

create index profiles_display_name_trgm_idx
  on public.profiles
  using gin (display_name extensions.gin_trgm_ops);
