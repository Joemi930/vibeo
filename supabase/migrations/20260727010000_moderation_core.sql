-- Migration : socle de modération (Phase 4, lot L1).
-- Table `moderation_logs` (journal d'audit, insertion service_role uniquement),
-- priorité de `reports` calculée automatiquement, vues admin `admin_stats` et
-- `admin_video_queue`. RLS activée dès la création, politiques nommées,
-- GRANT explicite (règle CLAUDE.md n°1-3). Référence : docs/ARCHITECTURE.md §3.

-- =============================================================================
-- 1) Enums.
-- =============================================================================
create type public.moderation_actor as enum ('ai', 'admin', 'system');

create type public.moderation_target as enum ('video', 'comment', 'application', 'report', 'user');

-- =============================================================================
-- 2) moderation_logs -- journal d'audit des décisions de modération. Écriture
--    strictement réservée à service_role (Edge Functions moderate-video,
--    verify-artist, process-report) : aucune politique INSERT/UPDATE/DELETE,
--    même patron que `view_events` (lecture seule pour les rôles applicatifs).
-- =============================================================================
create table public.moderation_logs (
  id          bigint generated always as identity primary key,
  actor       public.moderation_actor not null,
  -- NULL pour actor = 'ai' ou 'system' (pas de compte applicatif dédié) ;
  -- renseigné pour actor = 'admin'. ON DELETE SET NULL : la trace de
  -- modération survit à la suppression du compte admin qui a décidé.
  actor_id    uuid references public.profiles (id) on delete set null,
  target_type public.moderation_target not null,

  -- VOLONTAIREMENT SANS CLÉ ÉTRANGÈRE, même raisonnement que
  -- `reports.video_id`/`reports.comment_id` (20260726010000_social.sql §6) :
  -- une contrainte `on delete cascade` (ou même `set null` déclenchée par la
  -- suppression de la cible) s'exécute HORS RLS. Avec une FK, l'auteur d'un
  -- contenu sanctionné -- qui a le droit de supprimer SON PROPRE contenu via
  -- videos_delete_own / comments_delete_own -- effacerait silencieusement la
  -- trace de sa propre sanction en supprimant la cible. `target_id` reste donc
  -- une colonne `uuid` nue : la ligne de journal est immuable et permanente,
  -- quoi qu'il advienne de la cible référencée.
  target_id   uuid,
  action      text not null check (char_length(action) between 1 and 60),
  reason      text check (char_length(reason) <= 1000),
  metadata    jsonb,
  created_at  timestamptz not null default now()
);

comment on table public.moderation_logs is
  'Journal d''audit des décisions de modération (IA, admin, système). '
  'target_id est délibérément SANS clé étrangère (voir commentaire de colonne) '
  'afin que la trace survive à la suppression de la cible. Écriture réservée '
  'à service_role -- aucune politique INSERT/UPDATE/DELETE pour les rôles '
  'applicatifs, lecture admin uniquement.';

comment on column public.moderation_logs.target_id is
  'Identifiant de la cible (vidéo, commentaire, candidature, signalement, '
  'utilisateur), SANS contrainte de clé étrangère : une cascade FK s''exécute '
  'hors RLS et permettrait à l''auteur d''un contenu sanctionné d''effacer sa '
  'propre trace de modération en supprimant ce contenu.';

-- File d'audit générale, plus récente d'abord.
create index moderation_logs_created_idx
  on public.moderation_logs (created_at desc);

-- Historique de modération d'une cible précise (ex. récidive d'un artiste).
create index moderation_logs_target_idx
  on public.moderation_logs (target_type, target_id, created_at desc);

alter table public.moderation_logs enable row level security;

-- Seule politique : lecture admin. Aucune politique insert/update/delete --
-- écriture réservée à service_role, qui contourne la RLS par nature.
create policy moderation_logs_select_admin
  on public.moderation_logs
  for select
  to authenticated
  using (public.is_admin());

-- Jamais à `anon` : un visiteur non connecté n'a aucune raison de lire le
-- journal de modération, même filtré par RLS (défense en profondeur).
grant select on public.moderation_logs to authenticated;

-- =============================================================================
-- 3) reports.priority -- score de priorité calculé à l'insertion, figé à la
--    mise à jour. Réécriture (create or replace) de la fonction existante
--    `reports_guard_client_fields()` : tout son comportement actuel (forcer
--    status='pending', déduire target_kind/target_author_id) est conservé à
--    l'identique, INVOKER inchangé (les SELECT sur les cibles doivent passer
--    par la RLS de l'appelant, voir commentaire d'origine).
-- =============================================================================
alter table public.reports
  add column priority smallint not null default 0;

comment on column public.reports.priority is
  'Score de priorité de traitement (0-127), calculé à l''INSERT par '
  'reports_guard_client_fields() : motif, signalements concurrents sur la même '
  'cible, récidive de l''auteur ciblé. Figé à l''UPDATE (le client ne peut pas '
  'la remonter lui-même).';

create index reports_priority_idx
  on public.reports (status, priority desc, created_at);

-- ---------------------------------------------------------------------------
-- Helper SECURITY DEFINER pour le calcul de priority (appelé par
-- reports_guard_client_fields, INVOKER, ci-dessous).
--
-- POURQUOI SECURITY DEFINER ICI, EN CONTRASTE AVEC LE RESTE DE LA FONCTION
-- APPELANTE (délibérément INVOKER) : `reports` n'a aucune politique
-- `select_own` (règle du cahier des charges : un utilisateur ne relit jamais
-- ses propres signalements), et `moderation_logs` n'est lisible que par les
-- admins. Un appelant `authenticated` normal (le cas courant : un auditeur
-- qui signale un clip) ne voit donc AUCUNE ligne de `reports` ni de
-- `moderation_logs` par la RLS -- si ce calcul restait en INVOKER comme le
-- reste de la fonction, `count(*)`/`exists(...)` renverraient silencieusement
-- 0 pour tout le monde sauf un admin, et la priorité ne monterait jamais.
-- Ce comportement a été PIÉGÉ ET CORRIGÉ pendant l'écriture des tests
-- (rls_moderation_logs_test.sql, assertion 6) : un 2e signalement sur la même
-- cible ne faisait pas monter la priorité tant que cette fonction était
-- INVOKER.
--
-- Le résultat exposé au reste du trigger n'est qu'un ENTIER agrégé (un
-- bonus de score), jamais les lignes elles-mêmes : aucune fuite de données
-- vers l'appelant, seulement un effet sur une colonne qu'il ne relira de
-- toute façon jamais lui-même (reports n'a pas de politique select_own).
-- ---------------------------------------------------------------------------
create or replace function public.reports_compute_priority_bonus(
  p_video_id         uuid,
  p_comment_id       uuid,
  p_target_author_id uuid
)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_concurrent   integer;
  v_repeat_bonus smallint;
begin
  if p_video_id is not null then
    select count(*) into v_concurrent
      from public.reports r
     where r.video_id = p_video_id
       and r.status = 'pending';
  else
    select count(*) into v_concurrent
      from public.reports r
     where r.comment_id = p_comment_id
       and r.status = 'pending';
  end if;
  v_concurrent := least(coalesce(v_concurrent, 0) * 15, 45);

  if exists (
    select 1 from public.moderation_logs ml
     where ml.action in ('remove_video', 'reject_video', 'warn_author', 'remove_comment')
       and ml.target_id = p_target_author_id
  ) then
    v_repeat_bonus := 20;
  else
    v_repeat_bonus := 0;
  end if;

  return v_concurrent + v_repeat_bonus;
end;
$$;

comment on function public.reports_compute_priority_bonus(uuid, uuid, uuid) is
  'Bonus de priorité (signalements concurrents sur la même cible + récidive de '
  'l''auteur ciblé), SECURITY DEFINER : reports/moderation_logs ne sont pas '
  'lisibles par un appelant non-admin via RLS, ce calcul doit donc contourner '
  'la RLS pour rester correct quel que soit l''appelant. N''expose que le total '
  'agrégé, jamais les lignes sous-jacentes.';

revoke execute on function public.reports_compute_priority_bonus(uuid, uuid, uuid) from public, anon;
grant execute on function public.reports_compute_priority_bonus(uuid, uuid, uuid) to authenticated;

create or replace function public.reports_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_reason_base   smallint;
  v_computed      integer;
begin
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.created_at := now();

    -- Exactement une cible : la contrainte CHECK de la table est volontairement
    -- plus souple (elle doit accepter l'état « cible supprimée »), c'est donc
    -- ici que l'invariant de création est tenu.
    if (new.video_id is null) = (new.comment_id is null) then
      raise exception
        'Un signalement vise un clip OU un commentaire, jamais les deux ni aucun.'
        using errcode = '22023';
    end if;

    -- `target_kind` et `target_author_id` ne sont jamais pris du client : ils
    -- sont déduits et lus en base. Ils survivent à la suppression de la cible
    -- et sont la seule trace permettant à la modération de repérer un
    -- récidiviste qui efface ses contenus.
    if new.video_id is not null then
      new.target_kind := 'video';
      select v.artist_id into new.target_author_id
        from public.videos v
       where v.id = new.video_id;
    else
      new.target_kind := 'comment';
      select c.author_id into new.target_author_id
        from public.comments c
       where c.id = new.comment_id;
    end if;

    -- Fonction INVOKER (surtout pas SECURITY DEFINER : `current_user` vaudrait
    -- alors `postgres` et l'exemption ci-dessus désactiverait tout ce garde-fou).
    -- Les SELECT passent donc par la RLS de l'appelant : si la cible ne lui
    -- est pas visible, il n'avait de toute façon pas à la signaler.
    if new.target_author_id is null then
      raise exception 'Cible de signalement introuvable.'
        using errcode = '22023';
    end if;

    -- ---------------------------------------------------------------------
    -- Calcul de priority (Phase 4, lot L1). Voir commentaire de colonne.
    -- ---------------------------------------------------------------------
    v_reason_base := case new.reason
      when 'hate_speech'     then 60
      when 'sexual_content'  then 60
      when 'violence'        then 50
      when 'copyright'       then 40
      when 'misinformation'  then 30
      when 'spam'            then 20
      else 10 -- 'other'
    end;

    -- Signalements concurrents en attente sur la même cible (+15 chacun,
    -- plafonné à +45) et récidive de l'auteur ciblé (+20) : délégués à un
    -- helper SECURITY DEFINER, voir son commentaire -- `reports` et
    -- `moderation_logs` ne sont pas lisibles par un appelant non-admin via
    -- RLS, ce calcul doit donc contourner la RLS pour rester correct.
    v_computed := v_reason_base
      + public.reports_compute_priority_bonus(new.video_id, new.comment_id, new.target_author_id);
    new.priority := greatest(0, least(v_computed, 127));

    return new;
  end if;

  -- UPDATE côté client : de toute façon réservé aux admins par la RLS
  -- (reports_update_admin), mais on verrouille la cible et l'auteur par
  -- défense en profondeur.
  new.reporter_id := old.reporter_id;
  new.video_id := old.video_id;
  new.comment_id := old.comment_id;
  new.target_kind := old.target_kind;
  new.target_author_id := old.target_author_id;
  new.created_at := old.created_at;

  -- priority figée : jamais recalculée ni remontable côté client après coup.
  new.priority := old.priority;

  return new;
end;
$$;

comment on function public.reports_guard_client_fields() is
  'Verrouille reporter_id/cible/created_at ; force status=pending et '
  'reviewed_*=null à la création ; déduit target_kind et target_author_id '
  'depuis la base ; calcule priority (motif + signalements concurrents + '
  'récidive de l''auteur ciblé) à l''INSERT et la fige à l''UPDATE.';

-- Le trigger existant (reports_guard_client_fields_trigger) pointe déjà vers
-- cette fonction : `create or replace` suffit, aucun trigger à recréer.

-- =============================================================================
-- 4) Vues admin.
--
--    ATTENTION -- POINT LE PLUS FACILE À CASSER : ces vues s'exécutent avec
--    les droits de leur PROPRIÉTAIRE (postgres) et contournent donc la RLS
--    des tables de base qu'elles interrogent. Chacune DOIT porter sa propre
--    clause `where public.is_admin()` -- sans elle, n'importe quel compte
--    `authenticated` disposant du GRANT SELECT lirait des statistiques et une
--    file de modération globales.
-- =============================================================================

-- admin_stats : une seule ligne de statistiques globales.
--
-- `application_queue_count` n'est PAS inclus ici : la table
-- `artist_applications` n'existe pas encore à ce stade de la migration (elle
-- est créée par 20260727010100_artist_applications.sql, qui remplace cette
-- vue via `create or replace view` pour ajouter la colonne).
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
  1073741824::bigint as storage_bytes_limit
where public.is_admin();

comment on view public.admin_stats is
  'Statistiques globales (une seule ligne) pour le tableau de bord admin. '
  'Vue PROPRIÉTAIRE (contourne la RLS des tables sous-jacentes) : la clause '
  '`where public.is_admin()` est donc l''UNIQUE barrière -- ne jamais la '
  'retirer. Étendue par 20260727010100_artist_applications.sql '
  '(application_queue_count).';

-- admin_video_queue : vidéos nécessitant une action admin, avec le contexte
-- artiste et le résultat de modération.
create or replace view public.admin_video_queue
with (security_invoker = false) as
select
  v.id,
  v.artist_id,
  p.username as artist_username,
  p.display_name as artist_display_name,
  v.title,
  v.description,
  v.status,
  v.moderation_result,
  v.video_path,
  v.thumbnail_path,
  v.created_at
from public.videos v
join public.profiles p on p.id = v.artist_id
where v.status in ('processing', 'pending_moderation', 'rejected')
  and public.is_admin()
order by v.created_at;

comment on view public.admin_video_queue is
  'File de modération vidéo (processing/pending_moderation/rejected) avec '
  'contexte artiste. Vue PROPRIÉTAIRE : `where public.is_admin()` est '
  'l''UNIQUE barrière contre la RLS de public.videos -- ne jamais la retirer.';

grant select on public.admin_stats to authenticated;
grant select on public.admin_video_queue to authenticated;
