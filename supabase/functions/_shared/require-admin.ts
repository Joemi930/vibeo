// Vérification du rôle administrateur, côté serveur.
//
// Partagée par toutes les Edge Functions d'action admin. Le point important :
// **le rôle est relu dans la base avec la clé `service_role`**, jamais déduit
// d'une revendication du jeton ni d'un champ du corps de la requête.
//
// Pourquoi : un JWT Supabase reste valide jusqu'à son expiration. Un
// administrateur rétrogradé il y a dix minutes présente encore un jeton
// parfaitement signé. Si l'on faisait confiance à une revendication portée par
// ce jeton, il conserverait ses pouvoirs jusqu'à expiration. Une relecture en
// base coûte une requête et supprime entièrement ce trou.
//
// Le corps de la requête, lui, n'a évidemment aucune autorité : c'est l'attaque
// la plus élémentaire (`{"role":"admin"}`).

import {
  createClient,
  type SupabaseClient,
} from 'jsr:@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export type AdminContext = {
  adminClient: SupabaseClient;
  /// Identifiant de l'administrateur, à écrire dans `moderation_logs.actor_id`.
  adminId: string;
};

export type AdminGuardResult =
  | { ok: true; ctx: AdminContext }
  | { ok: false; response: Response };

/// Résout l'appelant et exige qu'il soit administrateur.
///
/// Renvoie un résultat étiqueté plutôt que de lever : l'appelant enchaîne
/// simplement sur `return guard.response` en cas de refus, ce qui garde les
/// codes HTTP et les messages au même endroit.
export async function requireAdmin(req: Request): Promise<AdminGuardResult> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error('require-admin: variables d\'environnement manquantes.');
    return {
      ok: false,
      response: jsonResponse({ error: 'Configuration serveur invalide.' }, 500),
    };
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) {
    return {
      ok: false,
      response: jsonResponse({ error: 'Authentification requise.' }, 401),
    };
  }

  // Le jeton est validé par GoTrue lui-même : sa signature est réellement
  // vérifiée, on ne se contente pas de le décoder.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await callerClient.auth.getUser(
    jwt,
  );
  if (userError || !user) {
    return {
      ok: false,
      response: jsonResponse({ error: 'Jeton invalide ou expiré.' }, 401),
    };
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: profile, error: profileError } = await adminClient
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  if (profileError) {
    console.error('require-admin: lecture du profil impossible', profileError);
    return {
      ok: false,
      response: jsonResponse({ error: 'Vérification impossible.' }, 500),
    };
  }

  if (profile?.role !== 'admin') {
    // 404 plutôt que 403 : ne pas confirmer à un curieux que cette fonction
    // existe et qu'il lui manque seulement le bon rôle.
    return {
      ok: false,
      response: jsonResponse({ error: 'Ressource introuvable.' }, 404),
    };
  }

  return { ok: true, ctx: { adminClient, adminId: user.id } };
}

/// Écrit une ligne au journal de modération.
///
/// Volontairement « au mieux » : si le journal échoue, l'action admin a déjà eu
/// lieu et il serait pire de la rejouer. L'échec est tracé côté serveur.
export async function logModeration(
  adminClient: SupabaseClient,
  entry: {
    actor: 'ai' | 'admin' | 'system';
    actorId?: string | null;
    targetType: 'video' | 'comment' | 'application' | 'report' | 'user';
    targetId?: string | null;
    action: string;
    reason?: string | null;
    metadata?: Record<string, unknown> | null;
  },
): Promise<void> {
  const { error } = await adminClient.from('moderation_logs').insert({
    actor: entry.actor,
    actor_id: entry.actorId ?? null,
    target_type: entry.targetType,
    target_id: entry.targetId ?? null,
    action: entry.action,
    reason: entry.reason ?? null,
    metadata: entry.metadata ?? null,
  });
  if (error) console.error('moderation_logs: écriture impossible', error);
}

/// Comparaison à temps constant, pour le secret partagé des tâches planifiées.
///
/// Un `===` sur une chaîne sort au premier octet différent : la durée de la
/// comparaison révèle la longueur du préfixe correct, ce qui permet de
/// reconstituer le secret octet par octet. Marginal sur un projet de cette
/// taille, mais le coût de faire juste est nul.
export function secretsMatch(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/// Garde des fonctions appelées par le planificateur, sans JWT utilisateur.
export function requireCronSecret(req: Request): Response | null {
  const expected = Deno.env.get('CRON_SECRET');
  if (!expected) {
    console.error('cron: CRON_SECRET absent.');
    return jsonResponse({ error: 'Configuration serveur invalide.' }, 500);
  }
  const provided = req.headers.get('x-vibeo-cron-secret') ?? '';
  if (!secretsMatch(provided, expected)) {
    return jsonResponse({ error: 'Ressource introuvable.' }, 404);
  }
  return null;
}
