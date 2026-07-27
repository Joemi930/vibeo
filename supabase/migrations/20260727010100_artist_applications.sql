-- Migration : candidatures artiste (Phase 4, lot L2). Table
-- `artist_applications`, droits par COLONNE (le candidat ne lit jamais
-- ai_score/ai_analysis/id_document_path/reviewed_by), rate limiting 1/semaine,
-- bucket `identity-docs` (aucune politique SELECT/DELETE, même pour les
-- admins -- voir §6). RLS activée dès la création, politiques nommées.
-- Référence : docs/ARCHITECTURE.md §3 (schéma cible) et §4 (protection
-- documents d'identité).

-- =============================================================================
-- 1) Enum de statut.
-- =============================================================================
create type public.application_status as enum (
  'pending',
  'manual_review',
  'approved',
  'rejected'
);

-- =============================================================================
-- 2) Table artist_applications.
-- =============================================================================
create table public.artist_applications (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles (id) on delete cascade,
  stage_name         text not null
                      check (char_length(btrim(stage_name)) between 2 and 60),
  links              jsonb not null default '[]'::jsonb
                      check (jsonb_typeof(links) = 'array' and jsonb_array_length(links) <= 5),
  statement          text not null
                      check (char_length(btrim(statement)) between 30 and 2000),
  id_document_path   text,
  document_purged_at timestamptz,
  ai_score           numeric(5,2) check (ai_score between 0 and 100),
  ai_analysis        jsonb,
  ai_provider        text,
  status             public.application_status not null default 'pending',
  decision_reason    text check (char_length(decision_reason) <= 500),
  reviewed_by        uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  decided_at         timestamptz
);

comment on table public.artist_applications is
  'Candidatures au statut artiste. Écrite par l''Edge Function verify-artist '
  '(service_role) uniquement -- aucune politique INSERT. Droits en lecture '
  'restreints PAR COLONNE (voir grants ci-dessous) : le candidat ne doit '
  'jamais lire ai_score/ai_analysis/id_document_path/reviewed_by.';

comment on column public.artist_applications.id_document_path is
  'Chemin (pas une URL) dans le bucket privé identity-docs. Jamais exposé au '
  'candidat via cette table (grant par colonne) ni via aucune vue -- une '
  'Edge Function dédiée délivre une URL signée de 5 min aux admins.';

comment on column public.artist_applications.document_purged_at is
  'Horodatage de la purge du document d''identité (cron pg, voir §7), NULL '
  'tant que le document existe encore dans le bucket.';

-- File de traitement admin, plus ancienne d'abord dans l'ordre naturel du tri
-- (created_at desc pour l'affichage "derniers arrivés").
create index artist_applications_status_created_idx
  on public.artist_applications (status, created_at desc);

-- "Mon historique de candidatures".
create index artist_applications_user_created_idx
  on public.artist_applications (user_id, created_at desc);

-- Une seule candidature OUVERTE par utilisateur (pending ou manual_review),
-- garantie par l'index et non par du code applicatif : même une écriture
-- directe en service_role (bug d'Edge Function) serait bloquée par Postgres.
-- Les candidatures approved/rejected sortent de l'index et n'empêchent donc
-- pas une nouvelle candidature future.
create unique index artist_applications_one_open_per_user_idx
  on public.artist_applications (user_id)
  where status in ('pending', 'manual_review');

-- ---------------------------------------------------------------------------
-- Garde-fou : le candidat ne peut QUE annuler sa propre candidature ouverte
-- (transition pending|manual_review -> rejected), tout le reste est figé.
-- INVOKER (comme comments_guard_client_fields, reports_guard_client_fields) :
-- pas de risque à laisser passer sous l'identité de l'appelant, la RLS
-- (artist_applications_update_own_cancel) filtre déjà les lignes visibles.
-- ---------------------------------------------------------------------------
create or replace function public.artist_applications_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    -- Seule transition autorisée côté client : annulation de sa propre
    -- candidature encore ouverte.
    if old.status not in ('pending', 'manual_review') or new.status <> 'rejected' then
      raise exception
        'Un candidat ne peut qu''annuler (rejeter) sa propre candidature en attente.'
        using errcode = '42501';
    end if;

    -- Toutes les autres colonnes sont figées : le candidat ne fournit qu'un
    -- changement de statut, jamais un contenu ni une valeur de décision.
    new.user_id := old.user_id;
    new.stage_name := old.stage_name;
    new.links := old.links;
    new.statement := old.statement;
    new.id_document_path := old.id_document_path;
    new.document_purged_at := old.document_purged_at;
    new.ai_score := old.ai_score;
    new.ai_analysis := old.ai_analysis;
    new.ai_provider := old.ai_provider;
    new.reviewed_by := old.reviewed_by;
    new.created_at := old.created_at;

    new.decided_at := now();
    new.decision_reason := 'Candidature annulée par le candidat.';

    return new;
  end if;

  return new;
end;
$$;

comment on function public.artist_applications_guard_client_fields() is
  'Le candidat ne peut que transitionner pending|manual_review -> rejected '
  '(annulation) ; toute autre colonne est figée à sa valeur précédente ; '
  'decided_at et decision_reason sont posés automatiquement sur cette '
  'annulation.';

create trigger artist_applications_guard_client_fields_trigger
  before update on public.artist_applications
  for each row
  execute function public.artist_applications_guard_client_fields();

-- ---------------------------------------------------------------------------
-- Rate limiting : 1 candidature par 7 jours glissants par utilisateur (règle
-- CLAUDE.md n°8). SECURITY DEFINER, même piège que videos/comments/reports :
-- identifier l'appelant par auth.role(), jamais current_user.
--
-- AVERTISSEMENT IMPORTANT : l'Edge Function `verify-artist` insère la
-- candidature en `service_role`, exactement le rôle exempté ci-dessous par
-- `auth.role() is distinct from 'authenticated'`. Le patron « exempter
-- service_role », qui protège partout ailleurs contre les faux positifs sur
-- les opérations d'administration, DÉSACTIVE ici la règle métier elle-même :
-- ce trigger n'arrêtera jamais un appel de verify-artist, même si l'Edge
-- Function contient un bug qui laisserait passer une 2e candidature dans la
-- semaine. La vérification AUTORITAIRE du quota 1/semaine doit donc être
-- faite dans le code de `verify-artist` elle-même ; ce trigger n'est qu'un
-- filet de sécurité contre un INSERT client direct (contournement de l'Edge
-- Function via l'API PostgREST -- qui de toute façon échouerait déjà faute de
-- politique INSERT, voir plus bas ; ce trigger reste néanmoins une défense en
-- profondeur si cette politique venait à changer).
-- ---------------------------------------------------------------------------
create or replace function public.artist_applications_enforce_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent_count integer;
begin
  if auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  select count(*)
    into recent_count
    from public.artist_applications
   where user_id = new.user_id
     and created_at >= now() - interval '7 days';

  if recent_count >= 1 then
    raise exception
      'Une seule candidature par semaine. Réessaie plus tard.'
      using errcode = '54000';
  end if;

  return new;
end;
$$;

comment on function public.artist_applications_enforce_rate_limit() is
  'Bloque une 2e candidature du même utilisateur sur 7 jours glissants. '
  'S''EXEMPTE pour service_role (donc pour verify-artist elle-même) -- voir '
  'l''avertissement ci-dessus : la vérification autoritaire vit dans l''Edge '
  'Function, ce trigger n''est qu''un filet contre un insert client direct.';

create trigger artist_applications_enforce_rate_limit_trigger
  before insert on public.artist_applications
  for each row
  execute function public.artist_applications_enforce_rate_limit();

revoke execute on function public.artist_applications_guard_client_fields() from public, anon, authenticated;
revoke execute on function public.artist_applications_enforce_rate_limit() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS + grants PAR COLONNE.
--
-- Pourquoi des grants par colonne et pas seulement des politiques RLS : la
-- RLS filtre des LIGNES, pas des colonnes. `artist_applications_select_own`
-- laisserait un candidat lire sa propre ligne EN ENTIER, y compris
-- ai_score/ai_analysis/id_document_path/reviewed_by. Dire à un fraudeur
-- pourquoi son document a été rejeté (score, analyse IA détaillée), c'est lui
-- livrer le mode d'emploi pour la prochaine tentative. Seul un GRANT SELECT
-- limité à une liste de colonnes empêche réellement PostgREST de les
-- restituer, quelle que soit la politique RLS.
-- ---------------------------------------------------------------------------
alter table public.artist_applications enable row level security;

create policy artist_applications_select_own
  on public.artist_applications
  for select
  to authenticated
  using (user_id = auth.uid());

create policy artist_applications_update_own_cancel
  on public.artist_applications
  for update
  to authenticated
  using (user_id = auth.uid() and status in ('pending', 'manual_review'))
  with check (user_id = auth.uid());

-- Aucune politique INSERT : la candidature naît exclusivement dans l'Edge
-- Function `verify-artist`, en service_role (qui contourne la RLS par
-- nature). Cela garantit qu'aucune ligne n'existe sans qu'une analyse IA ait
-- été effectivement déclenchée -- un INSERT direct via PostgREST échoue
-- toujours, quel que soit le contenu envoyé.
-- Aucune politique DELETE : le cycle de vie (annulation, décision) passe par
-- UPDATE (status), jamais par suppression.

grant select (id, user_id, stage_name, links, statement, status,
              decision_reason, created_at, decided_at, document_purged_at)
  on public.artist_applications to authenticated;
grant update (status) on public.artist_applications to authenticated;

-- =============================================================================
-- 3) Vue admin_artist_applications -- expose tout SAUF id_document_path (le
--    chemin ne sort jamais de la base ; remplacé par un booléen has_document).
-- =============================================================================
create or replace view public.admin_artist_applications
with (security_invoker = false) as
select
  a.id,
  a.user_id,
  p.username,
  p.display_name,
  a.stage_name,
  a.links,
  a.statement,
  (a.id_document_path is not null) as has_document,
  a.document_purged_at,
  a.ai_score,
  a.ai_analysis,
  a.ai_provider,
  a.status,
  a.decision_reason,
  a.reviewed_by,
  a.created_at,
  a.decided_at
from public.artist_applications a
join public.profiles p on p.id = a.user_id
where public.is_admin();

comment on view public.admin_artist_applications is
  'Vue admin des candidatures. N''expose JAMAIS id_document_path -- has_document '
  'le remplace. L''admin obtient une URL signée (5 min) auprès d''une Edge '
  'Function dédiée, jamais du chemin brut. Vue PROPRIÉTAIRE : '
  '`where public.is_admin()` est l''UNIQUE barrière contre la RLS -- ne '
  'jamais la retirer.';

grant select on public.admin_artist_applications to authenticated;

-- Étend admin_stats (créée par 20260727010000_moderation_core.sql, table
-- artist_applications indisponible à ce moment-là) avec la file d'attente des
-- candidatures.
create or replace view public.admin_stats
with (security_invoker = false) as
select
  (select count(*) from public.profiles) as user_count,
  (select count(*) from public.profiles where role = 'artist') as artist_count,
  (select count(*) from public.videos where status = 'published') as published_video_count,
  (select count(*) from public.videos where status in ('processing', 'pending_moderation')) as moderation_queue_count,
  (select count(*) from public.reports where status = 'pending') as open_report_count,
  (select coalesce(sum(view_count), 0) from public.videos) as total_view_count,
  (
    select coalesce(sum((o.metadata->>'size')::bigint), 0)
      from storage.objects o
     where o.bucket_id in ('videos', 'thumbnails', 'avatars', 'playlist-covers', 'identity-docs')
  ) as storage_bytes_used,
  1073741824::bigint as storage_bytes_limit,
  (select count(*) from public.artist_applications where status in ('pending', 'manual_review')) as application_queue_count
where public.is_admin();

comment on view public.admin_stats is
  'Statistiques globales (une seule ligne) pour le tableau de bord admin, y '
  'compris application_queue_count (candidatures pending + manual_review). '
  'Vue PROPRIÉTAIRE : `where public.is_admin()` est l''UNIQUE barrière -- ne '
  'jamais la retirer.';

-- =============================================================================
-- 4) Bucket identity-docs.
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'identity-docs',
  'identity-docs',
  false,
  5242880, -- 5 Mo
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- Écriture : uniquement dans son propre dossier, comme avatars/playlist-covers.
create policy identity_docs_storage_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'identity-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy identity_docs_storage_update_own
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'identity-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'identity-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- AUCUNE POLITIQUE SELECT, AUCUNE POLITIQUE DELETE -- POUR PERSONNE, ADMINS
-- COMPRIS. Ceci est un écart DÉLIBÉRÉ par rapport au patron habituel
-- (`is_admin()` autoriserait la lecture admin, comme pour moderation_logs ou
-- admin_video_queue).
--
-- Raisonnement (docs/ARCHITECTURE.md §4) : une politique `bucket_id =
-- 'identity-docs' and public.is_admin()` semble raisonnable, mais elle
-- signifie concrètement qu'un jeton d'admin volé (session compromise, JWT
-- exfiltré, XSS sur l'app admin) suffit à LISTER et TÉLÉCHARGER, depuis
-- l'API Storage publique de PostgREST, TOUTES les pièces d'identité jamais
-- uploadées par des candidats -- y compris celles de candidatures déjà
-- décidées et non encore purgées. Ce risque est disproportionné par rapport
-- au bénéfice (confort d'un accès direct par URL Storage).
--
-- Sans politique SELECT, PERSONNE ne peut lire le bucket via PostgREST/l'API
-- Storage cliente -- ni un candidat, ni un admin, ni anon. Seul
-- `service_role` (qui contourne la RLS par construction) peut lire les
-- objets, et il ne le fait qu'à travers DEUX Edge Functions auditées et
-- tracées au journal applicatif :
--   - `verify-artist` (traitement IA du document à la soumission),
--   - la fonction dédiée qui délivre à un admin une URL SIGNÉE de 5 minutes
--     pour une revue manuelle ponctuelle (jamais un accès permanent).
-- C'est strictement PLUS FORT qu'une politique `is_admin()`, car un jeton
-- volé ne donne alors accès à RIEN sur ce bucket -- il faudrait voler les
-- credentials service_role eux-mêmes, qui ne vivent jamais côté client.
--
-- Absence de politique DELETE pour la même raison symétrique : la suppression
-- est un acte de purge programmé (cron pg, §7 ci-dessous), pas une action
-- cliente, même admin.
--
-- Cette décision reprend exactement celle déjà prise en Phase 3.5 pour
-- `public.user_identities` (20260726020000_phase35.sql §1) : aucune politique
-- admin sur une donnée d'identité, l'accès administratif passe uniquement par
-- service_role.
-- ---------------------------------------------------------------------------

-- =============================================================================
-- 5) Purge des documents d'identité -- pourquoi elle n'est PAS ici.
--
--    La règle CLAUDE.md n°5 impose la suppression automatique du document
--    après décision, avec 30 jours de conservation maximum. La première
--    rédaction de cette migration le faisait en SQL :
--
--        delete from storage.objects where bucket_id = 'identity-docs' ...
--        update public.artist_applications set document_purged_at = now() ...
--
--    C'est FAUX, et faux d'une manière particulièrement dangereuse ici.
--
--    Supprimer une ligne de `storage.objects` retire l'entrée du catalogue,
--    mais **ne supprime pas l'objet stocké**. Le fichier reste sur le stockage
--    objet, consomme le quota de 1 Go pour toujours, et surtout : la base
--    affirme alors, via `document_purged_at`, qu'une pièce d'identité a été
--    effacée alors qu'elle existe encore. Une trace d'audit mensongère sur une
--    donnée d'identité est pire que pas de trace du tout — elle empêche de
--    découvrir le problème.
--
--    La suppression réelle exige l'API Storage, donc du HTTP, donc une Edge
--    Function. Le montage retenu est décrit dans la migration de planification
--    (`..._scheduling.sql`) : pg_cron déclenche, via pg_net, la fonction
--    `purge-identity-docs`, qui appelle `storage.remove()` et ne marque
--    `document_purged_at` **que si la suppression a réellement abouti**.
--
--    Conséquence pratique : aucune fonction de purge n'est définie ici, et il
--    ne faut pas en réintroduire une. Une purge en SQL pur est impossible.
-- =============================================================================

-- =============================================================================
-- 6) NOTE -- seed manuel obsolète.
--
--    20260725000000_seed_artist_role.sql promeut manuellement un utilisateur
--    au rôle `artist` "en attendant la Phase 4". Cette migration EST la
--    Phase 4 : la promotion passe désormais exclusivement par le pipeline
--    verify-artist (candidature -> analyse IA -> décision admin ou
--    auto-approbation selon score). Le seed manuel n'est PAS modifié ici
--    (une migration déjà appliquée ne se réécrit pas) mais est désormais
--    obsolète -- ne pas s'en servir comme modèle pour de futures promotions.
-- =============================================================================
