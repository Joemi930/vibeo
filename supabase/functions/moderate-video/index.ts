// Edge Function : moderate-video
//
// Phase 7 : la vérification IA est retirée. Cette fonction publie directement
// tout clip en attente (rattrapage des clips coincés en processing), ou ne fait
// rien si le clip est déjà publié.
//
// Déploiement :  supabase functions deploy moderate-video
// Secrets :      SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//                CRON_SECRET

import {
  createClient,
  type SupabaseClient,
} from 'jsr:@supabase/supabase-js@2';
import { z } from 'https://esm.sh/zod@3.23.8';

import {
  corsHeaders,
  jsonResponse,
  logModeration,
  secretsMatch,
} from '../_shared/require-admin.ts';

const requestSchema = z.union([
  z.object({ videoId: z.string().uuid() }).strict(),
  z.object({ mode: z.literal('requeue') }).strict(),
]);

async function moderateOne(
  adminClient: SupabaseClient,
  videoId: string,
  callerId: string | null,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const { data: video, error } = await adminClient
    .from('videos')
    .select('id, artist_id, status')
    .eq('id', videoId)
    .maybeSingle();

  if (error || !video) {
    return { status: 404, body: { error: 'Clip introuvable.' } };
  }
  if (callerId !== null && video.artist_id !== callerId) {
    return { status: 403, body: { error: 'Ce clip ne t\'appartient pas.' } };
  }
  if (video.status !== 'processing' && video.status !== 'pending_moderation') {
    return { status: 200, body: { status: video.status, skipped: true } };
  }

  const now = new Date().toISOString();

  // Phase 7 : publication directe, sans analyse IA.
  await adminClient
    .from('videos')
    .update({
      status: 'published',
      published_at: now,
      moderation_result: {
        state: 'approved',
        reason: 'Publication automatique (Phase 7).',
        at: now,
      },
    })
    .eq('id', videoId);

  await logModeration(adminClient, {
    actor: 'system',
    targetType: 'video',
    targetId: videoId,
    action: 'video_published',
    reason: 'Publication automatique (Phase 7).',
  });

  return { status: 200, body: { status: 'published' } };
}

/// Reprise planifiée : publie tout clip resté coincé en `processing`.
async function requeue(
  adminClient: SupabaseClient,
): Promise<Record<string, unknown>> {
  const { data: stuck } = await adminClient
    .from('videos')
    .select('id')
    .in('status', ['processing', 'pending_moderation'])
    .limit(50);

  let published = 0;
  for (const row of stuck ?? []) {
    const result = await moderateOne(adminClient, row.id as string, null);
    if (result.status === 200) published += 1;
  }
  return { published, total: stuck?.length ?? 0 };
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
    console.error('moderate-video: variables d\'environnement manquantes.');
    return jsonResponse({ error: 'Configuration serveur invalide.' }, 500);
  }

  let parsed;
  try {
    parsed = requestSchema.safeParse(await req.json());
  } catch {
    return jsonResponse({ error: 'Corps de requête invalide.' }, 400);
  }
  if (!parsed.success) {
    return jsonResponse({ error: 'Corps de requête invalide.' }, 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    if ('mode' in parsed.data) {
      // Reprise planifiée : pas de JWT utilisateur, garde par secret partagé.
      const expected = Deno.env.get('CRON_SECRET') ?? '';
      const provided = req.headers.get('x-vibeo-cron-secret') ?? '';
      if (expected.length === 0 || !secretsMatch(provided, expected)) {
        return jsonResponse({ error: 'Ressource introuvable.' }, 404);
      }
      return jsonResponse(await requeue(adminClient), 200);
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!jwt) return jsonResponse({ error: 'Authentification requise.' }, 401);

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await callerClient.auth
      .getUser(jwt);
    if (userError || !user) {
      return jsonResponse({ error: 'Jeton invalide ou expiré.' }, 401);
    }

    const outcome = await moderateOne(adminClient, parsed.data.videoId, user.id);
    return jsonResponse(outcome.body, outcome.status);
  } catch (error) {
    console.error('moderate-video: erreur inattendue', error);
    return jsonResponse({ error: 'La vérification a échoué.' }, 500);
  }
});
