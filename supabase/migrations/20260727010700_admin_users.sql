-- =============================================================================
-- Phase 7 — Vue admin_users pour la gestion des utilisateurs.
--
-- Liste tous les profils avec leur rôle et dates, lisible uniquement par les
-- administrateurs (RLS is_admin()). Exposée à PostgREST pour le nouvel onglet
-- « Utilisateurs » du dashboard admin.
-- =============================================================================

create or replace view public.admin_users
with (security_invoker = false) as
select
  p.id,
  p.username,
  p.display_name,
  p.avatar_url,
  p.bio,
  p.role,
  p.created_at
from public.profiles p
where public.is_admin()
order by p.created_at desc;

comment on view public.admin_users is
  'Liste des utilisateurs pour le dashboard admin. Vue PROPRIÉTAIRE : '
  '`where public.is_admin()` est l''UNIQUE barrière — ne jamais la retirer.';

grant select on public.admin_users to authenticated;
