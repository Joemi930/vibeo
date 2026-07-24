-- Durcissement des fonctions (advisories sécurité Supabase) :
-- 1. search_path verrouillé sur le trigger anti-escalade (comme handle_new_user).
-- 2. Fonctions trigger retirées de l'API REST : non appelables via /rpc par
--    anon/authenticated (elles n'ont de sens que dans le contexte d'un trigger).
alter function public.prevent_role_escalation() set search_path = '';

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.prevent_role_escalation() from public, anon, authenticated;
