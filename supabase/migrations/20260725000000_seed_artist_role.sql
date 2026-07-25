-- Migration : promotion manuelle d'un premier compte artiste.
-- Raccourci TEMPORAIRE assumé : en Phase 4, la promotion `listener -> artist`
-- se fera via le formulaire de candidature (`artist_applications`) + décision
-- IA/admin (voir docs/ARCHITECTURE.md §4). En attendant cette Phase 4, on a
-- besoin d'au moins un compte artiste pour développer/tester l'upload vidéo
-- de la Phase 2 : on promeut donc directement un profil connu par migration.
--
-- Cette migration s'exécute avec le rôle `postgres` (propriétaire des
-- migrations Supabase), qui fait partie des rôles exemptés par le trigger
-- `prevent_role_escalation()` (`current_user in ('service_role', 'postgres',
-- 'supabase_admin')` -- voir 20260724010000_profiles.sql). Le garde-fou lui-
-- même n'est PAS modifié : un utilisateur normal ne peut toujours pas
-- s'auto-promouvoir artiste.
update public.profiles
   set role = 'artist',
       display_name = coalesce(display_name, 'Artiste Vibeo')
 where id = '437d284b-03c4-4264-810c-4e764bd10f2e';
