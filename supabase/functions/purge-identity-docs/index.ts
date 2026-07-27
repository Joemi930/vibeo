// Edge Function : purge-identity-docs
//
// Supprime les pièces d'identité devenues inutiles (architecture §4 :
// minimisation des données, 30 jours maximum).
//
// **Pourquoi une Edge Function et pas un simple cron SQL**, alors que le prompt
// de phase disait « cron pg de suppression des documents » : supprimer une
// ligne de `storage.objects` en SQL **ne supprime pas l'objet sous-jacent**. On
// obtiendrait un blob orphelin, invisible de la base, qui consomme le quota de
// 1 Go pour toujours — et surtout une pièce d'identité qu'on croirait effacée et
// qui existerait encore. La suppression doit passer par l'API Storage.
// Le planificateur pg_cron appelle donc cette fonction via pg_net.
//
// Deux critères de purge :
// 1. candidature décidée (`approved`/`rejected`) — normalement déjà purgée par
//    `verify-artist` à la décision ; ceci rattrape les échecs de cette purge ;
// 2. candidature de plus de 30 jours quel que soit son statut — le plafond
//    absolu de conservation, y compris pour un dossier oublié en revue manuelle.
//
// Appelée sans JWT utilisateur : la garde est un secret partagé, comparé à temps
// constant. Nécessite `verify_jwt = false` dans `supabase/config.toml`.
//
// Déploiement :
//   supabase functions deploy purge-identity-docs --no-verify-jwt
// Secrets requis :
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CRON_SECRET

import { createClient } from 'jsr:@supabase/supabase-js@2';

import {
  corsHeaders,
  jsonResponse,
  logModeration,
  requireCronSecret,
} from '../_shared/require-admin.ts';

const BUCKET = 'identity-docs';
const MAX_RETENTION_DAYS = 30;

/// Traité par lots : une purge qui déborde le temps d'exécution laisserait des
/// documents derrière elle sans que rien ne le signale. Le cron repasse chaque
/// jour, un reliquat est donc rattrapé au tour suivant.
const BATCH_SIZE = 200;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Méthode non supportée.' }, 405);
  }

  const denied = requireCronSecret(req);
  if (denied) return denied;

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('purge-identity-docs: variables d\'environnement manquantes.');
    return jsonResponse({ error: 'Configuration serveur invalide.' }, 500);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const cutoff = new Date(
    Date.now() - MAX_RETENTION_DAYS * 24 * 3600 * 1000,
  ).toISOString();

  const { data: rows, error } = await adminClient
    .from('artist_applications')
    .select('id, user_id, id_document_path, status, created_at')
    .not('id_document_path', 'is', null)
    .or(`status.in.(approved,rejected),created_at.lt.${cutoff}`)
    .limit(BATCH_SIZE);

  if (error) {
    console.error('purge-identity-docs: lecture impossible', error);
    return jsonResponse({ error: 'Purge impossible.' }, 500);
  }
  if (!rows || rows.length === 0) {
    return jsonResponse({ purged: 0 }, 200);
  }

  const now = new Date().toISOString();
  let purged = 0;

  for (const row of rows) {
    const path = row.id_document_path as string;
    const { error: removeError } = await adminClient.storage
      .from(BUCKET)
      .remove([path]);
    if (removeError) {
      // On ne marque PAS la ligne comme purgée : le prochain passage réessaiera.
      // Écrire `document_purged_at` ici produirait une trace mensongère — la
      // base affirmerait que le document a disparu alors qu'il est toujours là.
      console.error(`purge-identity-docs: échec sur ${row.id}`, removeError);
      continue;
    }

    const { error: updateError } = await adminClient
      .from('artist_applications')
      .update({ id_document_path: null, document_purged_at: now })
      .eq('id', row.id);
    if (updateError) {
      console.error(`purge-identity-docs: mise à jour ${row.id}`, updateError);
      continue;
    }

    purged += 1;
    await logModeration(adminClient, {
      actor: 'system',
      targetType: 'application',
      targetId: row.id as string,
      action: 'identity_document_purged',
      reason: row.status === 'approved' || row.status === 'rejected'
        ? 'Candidature décidée.'
        : `Conservation maximale de ${MAX_RETENTION_DAYS} jours atteinte.`,
    });
  }

  return jsonResponse({ purged, examined: rows.length }, 200);
});
