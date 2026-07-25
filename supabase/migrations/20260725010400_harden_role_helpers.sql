-- Migration : durcissement des helpers de rôle (advisors sécurité Supabase
-- « anon_security_definer_function_executable »).
--
-- Constat : `revoke execute ... from public` ne retire PAS le droit au rôle
-- `anon`, qui conserve un privilège explicite. `is_admin()` et `is_artist()`
-- restaient donc appelables sans être connecté, via /rest/v1/rpc/is_admin.
--
-- Or aucune politique ouverte à `anon` ne les appelle : elles ne servent que
-- dans des politiques `to authenticated` (`videos_select_admin`,
-- `videos_insert_own_artist`, `videos_storage_select_admin`, …). On les ferme
-- donc à `anon`, par principe de moindre privilège.
--
-- `record_view` reste volontairement ouverte à `anon` : un visiteur en mode
-- invité doit pouvoir faire comptabiliser une vue (c'est son seul chemin
-- d'écriture, et la fonction applique elle-même la règle des 10 secondes et
-- l'anti-spam).
revoke execute on function public.is_admin() from anon;
revoke execute on function public.is_artist(uuid) from anon;
