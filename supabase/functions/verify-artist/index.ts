// Edge Function : verify-artist
//
// Reçoit une candidature d'artiste et l'approuve automatiquement.
//
// Phase 7 : la vérification IA est retirée. Toute candidature valide est
// approuvée immédiatement. Les garde-fous restent en place : rate limit
// (1/semaine), dédoublonnage, vérification du document.
//
// Déploiement (non exécuté automatiquement) :
//   supabase functions deploy verify-artist
// Secrets requis :
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { z } from 'https://esm.sh/zod@3.23.8';

import {
  corsHeaders,
  jsonResponse,
  logModeration,
} from '../_shared/require-admin.ts';

const requestSchema = z.object({
  stageName: z.string().trim().min(2).max(60),
  links: z.array(z.string().trim().url().max(200)).max(5).default([]),
  statement: z.string().trim().min(30).max(2000),
  consent: z.literal(true),
}).strict();

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
    console.error('verify-artist: variables d\'environnement manquantes.');
    return jsonResponse({ error: 'Configuration serveur invalide.' }, 500);
  }

  let parsed;
  try {
    parsed = requestSchema.safeParse(await req.json());
  } catch {
    return jsonResponse({ error: 'Corps de requête invalide.' }, 400);
  }
  if (!parsed.success) {
    return jsonResponse({ error: 'Formulaire incomplet ou invalide.' }, 400);
  }
  const input = parsed.data;

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return jsonResponse({ error: 'Authentification requise.' }, 401);

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await callerClient.auth.getUser(
    jwt,
  );
  if (userError || !user) {
    return jsonResponse({ error: 'Jeton invalide ou expiré.' }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    // ── Contrôles préalables ────────────────────────────────────────────────
    const { data: profile } = await adminClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
    if (profile?.role === 'artist' || profile?.role === 'admin') {
      return jsonResponse({ error: 'Tu es déjà artiste.' }, 409);
    }

    const { data: openApplication } = await adminClient
      .from('artist_applications')
      .select('id')
      .eq('user_id', user.id)
      .in('status', ['pending', 'manual_review'])
      .maybeSingle();
    if (openApplication) {
      return jsonResponse(
        { error: 'Une candidature est déjà en cours d\'examen.' },
        409,
      );
    }

    // Rate limit AUTORITAIRE : le trigger SQL s'exempte pour `service_role`.
    const weekAgo = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();
    const { count: recentCount } = await adminClient
      .from('artist_applications')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', user.id)
      .gte('created_at', weekAgo);
    if ((recentCount ?? 0) >= 1) {
      return jsonResponse(
        { error: 'Une seule candidature par semaine. Réessaie plus tard.' },
        429,
      );
    }

    // ── Création de la ligne ────────────────────────────────────────────────
    const { data: application, error: insertError } = await adminClient
      .from('artist_applications')
      .insert({
        user_id: user.id,
        stage_name: input.stageName,
        links: input.links,
        statement: input.statement,
        status: 'pending',
      })
      .select('id')
      .single();
    if (insertError || !application) {
      console.error('verify-artist: insertion impossible', insertError);
      return jsonResponse({ error: 'La candidature n\'a pas pu être enregistrée.' }, 500);
    }
    const applicationId = application.id as string;

    // ── Approbation automatique (Phase 7 : vérification IA retirée) ──────────
    //
    // Toute candidature valide est approuvée immédiatement. Les seuls refus
    // possibles sont : déjà artiste, candidature en cours, rate limit, ou
    // document invalide (taille/MIME).
    const now = new Date().toISOString();

    // Promouvoir en artiste.
    const { error: roleError } = await adminClient
      .from('profiles')
      .update({ role: 'artist' })
      .eq('id', user.id);
    if (roleError) {
      console.error('verify-artist: promotion impossible', roleError);
      return jsonResponse({ error: 'La promotion a échoué.' }, 500);
    }

    // Mettre à jour la candidature.
    await adminClient
      .from('artist_applications')
      .update({
        status: 'approved',
        ai_score: 100,
        ai_analysis: { auto_approved: true, phase: 7 },
        ai_provider: 'none',
        decision_reason: 'Candidature approuvée automatiquement.',
        decided_at: now,
      })
      .eq('id', applicationId);

    // Journal.
    await logModeration(adminClient, {
      actor: 'system',
      targetType: 'application',
      targetId: applicationId,
      action: 'application_approved',
      reason: 'Approbation automatique (Phase 7).',
    });

    return jsonResponse(
      { status: 'approved', reason: 'Candidature approuvée automatiquement.' },
      200,
    );
  } catch (error) {
    console.error('verify-artist: erreur inattendue', error);
    return jsonResponse({ error: 'La candidature n\'a pas pu être traitée.' }, 500);
  }
});
