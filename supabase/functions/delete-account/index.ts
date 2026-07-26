// Edge Function : delete-account
//
// Supprime définitivement le compte de l'appelant. C'est la SEULE voie
// possible : `supabase.auth.admin.deleteUser` exige la clé `service_role`,
// qui ne doit jamais approcher le code Flutter (règle CLAUDE.md n°2).
//
// Choix de conception :
// - L'identifiant du compte à supprimer est déduit du JWT porté par
//   l'en-tête `Authorization`, JAMAIS d'un champ du corps de la requête —
//   sans quoi n'importe quel utilisateur connecté pourrait faire supprimer
//   le compte d'un autre en indiquant son id dans le JSON.
// - Le corps de la requête est validé avec Zod (règle n°7) : un objet vide
//   `{}` est le seul contenu attendu ; `.strict()` rejette tout champ
//   surnuméraire (ex. un `userId` qu'un client mal intentionné tenterait de
//   glisser, même si de toute façon il serait ignoré par la logique
//   ci-dessous — défense en profondeur).
// - `auth.admin.deleteUser` est appelé EN PREMIER : il déclenche la cascade
//   Postgres déjà en place (`profiles.id references auth.users(id) on delete
//   cascade`, elle-même la racine de `videos`, `user_identities`, `likes`,
//   `comments`, `subscriptions`, `playlists`, etc.) — rien à répliquer ici.
// - Les objets Storage (`avatars`, `videos`, `thumbnails`, `playlist-covers`,
//   convention plate `<uid>/<fichier>`) sont nettoyés ENSUITE, au mieux : les
//   buckets ne sont liés par aucune clé étrangère, la cascade ne les touche
//   pas. Voir le commentaire dans le corps pour la raison de cet ordre — il
//   est délibéré, ne pas l'inverser.
// - IMPORTANT — les signalements (`reports`) SURVIVENT à cette suppression
//   par construction du schéma, pas par un traitement spécial de cette
//   fonction : `reports.target_author_id` et `reports.video_id` /
//   `comment_id` sont en `on delete set null` (voir
//   `20260726010000_social.sql` §6), donc la ligne de signalement reste,
//   seule sa cible devient NULL. Un utilisateur signalé ne peut donc pas
//   faire disparaître les preuves en supprimant son compte. Vérifié dans la
//   migration avant d'écrire cette fonction — à ne jamais casser.
//
// Déploiement (non exécuté par cet agent) :
//   supabase functions deploy delete-account
// Secrets requis (déjà standard sur tout projet Supabase, à vérifier) :
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { z } from 'https://esm.sh/zod@3.23.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Corps attendu : rien. `.strict()` rejette tout champ surnuméraire plutôt
// que de l'ignorer silencieusement.
const requestSchema = z.object({}).strict();

// Buckets où l'utilisateur peut avoir déposé des fichiers, convention
// `<uid>/...` dans chacun (voir migrations storage correspondantes).
const USER_OWNED_BUCKETS = [
  'avatars',
  'videos',
  'thumbnails',
  'playlist-covers',
] as const;

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Taille de page pour l'énumération du stockage. Une seule passe de 1000
// laisserait des fichiers derrière elle dès qu'un artiste dépasse ce nombre
// d'objets : on boucle donc jusqu'à épuisement.
const STORAGE_PAGE_SIZE = 1000;

async function deleteUserStorageObjects(
  adminClient: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  for (const bucket of USER_OWNED_BUCKETS) {
    let offset = 0;
    // Les chemins sont plats (`<uid>/<fichier>`) dans les quatre buckets :
    // aucun sous-dossier à parcourir récursivement.
    for (;;) {
      const { data: entries, error: listError } = await adminClient.storage
        .from(bucket)
        .list(userId, { limit: STORAGE_PAGE_SIZE, offset });
      if (listError) {
        // Un bucket sans dossier pour cet utilisateur n'est pas une erreur
        // bloquante : on journalise et on passe au bucket suivant.
        console.error(
          `delete-account: list ${bucket}/${userId} failed`,
          listError,
        );
        break;
      }
      if (!entries || entries.length === 0) break;

      const paths = entries.map((entry) => `${userId}/${entry.name}`);
      const { error: removeError } = await adminClient.storage
        .from(bucket)
        .remove(paths);
      if (removeError) {
        console.error(
          `delete-account: remove ${bucket}/${userId} failed`,
          removeError,
        );
        // Inutile de continuer à paginer si la suppression échoue : on ne
        // ferait que répéter la même erreur sur les pages suivantes.
        break;
      }

      if (entries.length < STORAGE_PAGE_SIZE) break;
      offset += entries.length;
    }
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Méthode non supportée.' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error('delete-account: variables d\'environnement manquantes.');
    return jsonResponse({ error: 'Configuration serveur invalide.' }, 500);
  }

  // Corps : vide attendu, mais on tolère un corps réellement vide (pas de
  // JSON) avant de valider avec Zod.
  let rawBody: unknown = {};
  const text = await req.text();
  if (text.trim().length > 0) {
    try {
      rawBody = JSON.parse(text);
    } catch {
      return jsonResponse({ error: 'Corps de requête invalide.' }, 400);
    }
  }
  const parsed = requestSchema.safeParse(rawBody);
  if (!parsed.success) {
    return jsonResponse({ error: 'Corps de requête invalide.' }, 400);
  }

  // Identifie l'appelant depuis SON PROPRE jeton (jamais depuis le corps) :
  // un client anon-key + le JWT de la requête suffit à résoudre l'utilisateur
  // sans avoir besoin du service_role pour cette étape.
  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) {
    return jsonResponse({ error: 'Authentification requise.' }, 401);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userError,
  } = await callerClient.auth.getUser(jwt);
  if (userError || !user) {
    return jsonResponse({ error: 'Jeton invalide ou expiré.' }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    // ORDRE VOULU : le compte d'abord, les fichiers ensuite.
    //
    // L'inverse — nettoyer le stockage puis supprimer le compte — a un chemin
    // d'échec inacceptable : si `deleteUser` rate, l'utilisateur a perdu tous
    // ses clips ET garde son compte, sans rien avoir demandé de tel. Dans ce
    // sens-ci, le pire échec possible laisse des fichiers orphelins qui
    // consomment du quota — récupérable côté administration, alors qu'une
    // vidéo effacée ne revient pas.
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      user.id,
    );
    if (deleteError) {
      console.error('delete-account: deleteUser failed', deleteError);
      return jsonResponse(
        { error: 'Échec de la suppression du compte.' },
        500,
      );
    }

    // Nettoyage au mieux : le compte est déjà supprimé, l'opération a réussi
    // du point de vue de l'utilisateur même si un bucket résiste.
    await deleteUserStorageObjects(adminClient, user.id);

    return jsonResponse({ success: true }, 200);
  } catch (error) {
    console.error('delete-account: erreur inattendue', error);
    return jsonResponse({ error: 'Échec de la suppression du compte.' }, 500);
  }
});
