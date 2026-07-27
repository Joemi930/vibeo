-- Migration : planificateur (Phase 5) -- rafraîchissement des tendances,
-- purge des documents d'identité, relance de la file de modération.
--
-- SÉPARÉE DÉLIBÉRÉMENT des migrations de schéma (discovery.sql,
-- artist_applications.sql) : c'est la SEULE migration susceptible d'échouer
-- différemment en local qu'en cloud (extensions pg_cron/pg_net absentes ou
-- désactivées localement, Vault vide tant que le propriétaire du projet n'a
-- pas créé ses secrets). On veut pouvoir la rejouer, l'ignorer ou la corriger
-- sans jamais toucher au schéma applicatif -- une migration de schéma qui
-- échouerait pour une raison d'infrastructure cron bloquerait `db reset` en
-- entier, y compris pour des développeurs qui n'ont pas besoin du cron.
--
-- AVERTISSEMENT IMPORTANT (à connaître pour toute démo) : un projet Supabase
-- gratuit est automatiquement MIS EN PAUSE après 7 jours d'inactivité API.
-- Le planificateur pg_cron s'arrête avec lui -- les tendances restent figées
-- sur leur dernier calcul, les documents d'identité en attente de purge ne
-- sont plus traités, la file de modération n'est plus relancée. Reprendre le
-- projet (dashboard Supabase) ne rejoue PAS automatiquement les tâches
-- manquées ; le premier refresh suivant la reprise reste correct (les
-- fenêtres glissantes de trending_videos se recalculent sur les données
-- réelles), mais toute démo reprise après une pause doit prévoir un appel
-- manuel à `select public.refresh_trending_videos();` si l'attente d'une
-- heure n'est pas acceptable.
-- =============================================================================

-- =============================================================================
-- 1) Extensions -- tolérantes à l'absence (environnement local minimal).
-- =============================================================================
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      create extension pg_cron with schema pg_catalog;
    exception
      when insufficient_privilege or feature_not_supported then
        raise notice 'pg_cron indisponible dans cet environnement -- planification ignorée.';
    end;
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    begin
      create extension pg_net with schema extensions;
    exception
      when insufficient_privilege or feature_not_supported then
        raise notice 'pg_net indisponible dans cet environnement -- les tâches HTTP seront ignorées.';
    end;
  end if;
end;
$$;

-- =============================================================================
-- 2) Secrets Vault -- À CRÉER MANUELLEMENT PAR LE PROPRIÉTAIRE DU PROJET.
--
--    Ni cet agent ni l'orchestrateur ne manipulent de secrets : aucune valeur
--    n'est inventée ni codée en dur ici. Ce qui suit est un COMMENTAIRE, à
--    exécuter tel quel (avec les vraies valeurs) par le propriétaire du
--    projet, une seule fois, dans le SQL Editor du dashboard Supabase (ou via
--    `supabase secrets`/Vault en CLI selon la version) :
--
--    -- >>> À EXÉCUTER MANUELLEMENT PAR LE PROPRIÉTAIRE DU PROJET, PAS ICI <<<
--    -- select vault.create_secret(
--    --   'https://<project-ref>.supabase.co',   -- URL réelle du projet
--    --   'vibeo_project_url'
--    -- );
--    -- select vault.create_secret(
--    --   '<valeur générée aléatoirement, longue, jamais réutilisée ailleurs>',
--    --   'vibeo_cron_secret'                     -- doit correspondre à la
--    --                                            -- variable d'env CRON_SECRET
--    --                                            -- des Edge Functions purge-
--    --                                            -- identity-docs / moderate-video
--    -- );
--    -- <<< FIN DU BLOC À EXÉCUTER MANUELLEMENT >>>
--
--    Les tâches HTTP ci-dessous lisent ces secrets via `vault.decrypted_secrets`
--    à CHAQUE exécution (pas de valeur figée dans la définition du cron) :
--    si les secrets n'existent pas encore, les sous-requêtes renvoient NULL et
--    `net.http_post` échoue proprement (URL/en-tête NULL) sans jamais exposer
--    de valeur par défaut inventée.
-- =============================================================================

-- =============================================================================
-- 3) Tâches planifiées -- toutes gardées par la présence effective de pg_cron.
-- =============================================================================
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then

    -- Rafraîchissement des tendances : SQL pur, aucun réseau, aucune
    -- dépendance à Vault/pg_net -- fonctionne même si les secrets n'ont pas
    -- encore été créés par le propriétaire du projet.
    perform cron.schedule(
      'vibeo-refresh-trending',
      '4 * * * *',
      $sql$select public.refresh_trending_videos();$sql$
    );

    -- Purge des documents d'identité décidés/expirés : appel HTTP vers
    -- l'Edge Function purge-identity-docs (voir son commentaire d'en-tête --
    -- la suppression réelle de l'objet Storage ne peut PAS se faire en SQL
    -- pur). Nécessite pg_net ET les deux secrets Vault ci-dessus.
    if exists (select 1 from pg_extension where extname = 'pg_net') then
      perform cron.schedule(
        'vibeo-purge-identity-docs',
        '17 3 * * *',
        $sql$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'vibeo_project_url')
                 || '/functions/v1/purge-identity-docs',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-vibeo-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'vibeo_cron_secret')
          ),
          body := '{}'::jsonb
        );
        $sql$
      );

      -- Relance de la file de modération (rattrape les vidéos restées
      -- bloquées en `processing`/`pending_moderation` après un échec
      -- transitoire de l'IA, ou une invocation manquée de moderate-video à
      -- l'upload).
      perform cron.schedule(
        'vibeo-requeue-moderation',
        '*/15 * * * *',
        $sql$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'vibeo_project_url')
                 || '/functions/v1/moderate-video',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-vibeo-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'vibeo_cron_secret')
          ),
          body := '{"mode":"requeue"}'::jsonb
        );
        $sql$
      );
    else
      raise notice 'pg_net indisponible : tâches HTTP (purge identité, relance modération) non planifiées.';
    end if;

  else
    raise notice 'pg_cron indisponible : aucune tâche planifiée dans cet environnement.';
  end if;
end;
$$;
