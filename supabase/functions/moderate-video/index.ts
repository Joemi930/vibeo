// Edge Function : moderate-video
//
// Analyse un clip fraîchement téléversé (titre, description, miniature) et
// décide de sa publication (docs/ARCHITECTURE.md §5).
//
// ── Pourquoi c'est le client qui appelle, et pourquoi ce n'est pas contournable
//
// Trois montages étaient possibles ; deux sont mauvais :
//   - un webhook base de données (pg_net sur INSERT) est du « tire et oublie » :
//     ni réessai, ni visibilité, ni code de retour ;
//   - une fonction `publish-video` remplaçant l'insertion client réécrirait tout
//     le chemin d'upload et perdrait les politiques déjà auditées.
//
// Retenu : le client insère puis appelle cette fonction. L'objection évidente —
// « le client peut ne pas appeler » — est levée non par de la discipline, mais
// par une modification du trigger `videos_guard_client_fields()` : le client ne
// peut plus créer une vidéo autrement qu'en `processing`. Une vidéo qui n'est
// jamais soumise à modération reste donc invisible de tous. Contourner l'appel
// ne fait que se pénaliser soi-même.
//
// Le passage en `pending_moderation` est fait ICI, en `service_role`, que le
// trigger exempte. Le client ne pose jamais ce statut : la contrainte de la
// spécification est respectée sans exception ni contorsion.
//
// ── Rien ne reste bloqué
//
// Cette fonction est **idempotente** : elle accepte `processing` comme
// `pending_moderation`. Trois filets s'appuient dessus — bouton « Relancer la
// vérification » après l'upload et dans le Studio, et une reprise planifiée
// (`mode: "requeue"`) qui ré-injecte les clips en souffrance. Au-delà de 24 h,
// la reprise force `pending_moderation`, c'est-à-dire la file d'attente admin :
// **on échoue vers l'humain, jamais vers la publication automatique ni vers les
// limbes.**
//
// Déploiement :  supabase functions deploy moderate-video
// Secrets :      SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//                GEMINI_API_KEY (ou DEEPSEEK), CRON_SECRET

import {
  createClient,
  type SupabaseClient,
} from 'jsr:@supabase/supabase-js@2';
import { z } from 'https://esm.sh/zod@3.23.8';

import { getAiProvider } from '../_shared/ai-provider.ts';
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

const moderationSchema = z.object({
  verdict: z.enum(['clean', 'flagged', 'uncertain']),
  category: z.enum([
    'none',
    'hate_speech',
    'sexual_content',
    'violence',
    'copyright',
    'misinformation',
    'spam',
  ]),
  confidence: z.number().int().min(0).max(100),
  reason: z.string().max(200).optional(),
}).strict();

const moderationJsonSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['verdict', 'category', 'confidence'],
  properties: {
    verdict: { type: 'string', enum: ['clean', 'flagged', 'uncertain'] },
    category: {
      type: 'string',
      enum: [
        'none',
        'hate_speech',
        'sexual_content',
        'violence',
        'copyright',
        'misinformation',
        'spam',
      ],
    },
    confidence: { type: 'integer', minimum: 0, maximum: 100 },
    reason: { type: 'string', maxLength: 200 },
  },
};

/// Motifs affichés à l'artiste dans le Studio. Rédigés ici, en français, plutôt
/// que repris de la réponse du modèle : un texte généré n'a rien à faire
/// directement sous les yeux d'un utilisateur.
const CATEGORY_REASONS: Record<string, string> = {
  hate_speech: 'Le titre ou la description contient des propos haineux.',
  sexual_content: 'Le contenu annoncé est à caractère sexuel.',
  violence: 'Le contenu annoncé est violent.',
  copyright: 'Le clip semble porter atteinte à des droits d\'auteur.',
  misinformation: 'Le contenu annoncé relaie une information trompeuse.',
  spam: 'Le titre ou la description ressemble à du spam.',
  none: 'Ce clip a été retiré par la modération.',
};

/// Au-delà de ce délai, un clip bloqué part en file admin plutôt que d'être
/// analysé à nouveau indéfiniment.
const GIVE_UP_HOURS = 24;
const STALE_MINUTES = 30;

function prompt(title: string, description: string | null): string {
  return [
    'Tu modères le titre et la description d\'un clip musical publié sur une',
    'plateforme grand public.',
    '',
    `Titre : ${title}`,
    `Description : ${description ?? '(aucune)'}`,
    '',
    'Détermine :',
    '- verdict : « clean » si rien ne pose problème, « flagged » si le contenu',
    '  enfreint clairement les règles, « uncertain » en cas de doute.',
    '- category : la nature du problème, ou « none ».',
    '- confidence : ta confiance, de 0 à 100.',
    '',
    'Sois mesuré : un titre cru, provocateur ou en argot n\'est pas en soi une',
    'infraction — le rap et le drill en font un usage courant et légitime.',
    'Ne signale que ce qui est manifestement problématique.',
    '',
    'Réponds uniquement selon le schéma JSON fourni.',
  ].join('\n');
}

async function moderateOne(
  adminClient: SupabaseClient,
  videoId: string,
  callerId: string | null,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const { data: video, error } = await adminClient
    .from('videos')
    .select('id, artist_id, title, description, thumbnail_path, status')
    .eq('id', videoId)
    .maybeSingle();

  if (error || !video) {
    return { status: 404, body: { error: 'Clip introuvable.' } };
  }
  // Un artiste ne fait modérer que ses propres clips. `callerId === null`
  // signifie « appel du planificateur », déjà authentifié par le secret partagé.
  if (callerId !== null && video.artist_id !== callerId) {
    return { status: 403, body: { error: 'Ce clip ne t\'appartient pas.' } };
  }
  if (video.status !== 'processing' && video.status !== 'pending_moderation') {
    // Idempotence : rejouer sur un clip déjà décidé n'est pas une erreur, mais
    // ne doit surtout pas le republier.
    return { status: 200, body: { status: video.status, skipped: true } };
  }

  await adminClient
    .from('videos')
    .update({ status: 'pending_moderation' })
    .eq('id', videoId);

  const provider = getAiProvider();
  const result = await provider.analyzeText(
    prompt(video.title as string, video.description as string | null),
    moderationJsonSchema,
  );

  let verdict: z.infer<typeof moderationSchema> | null = null;
  if (result.ok) {
    const validated = moderationSchema.safeParse(result.data);
    if (validated.success) verdict = validated.data;
  }

  const now = new Date().toISOString();

  if (verdict === null) {
    // Analyse indisponible : le clip reste dans la file admin. Ni publication
    // en aveugle, ni rejet pour cause de panne.
    await adminClient
      .from('videos')
      .update({
        moderation_result: {
          state: 'pending_admin',
          provider: provider.name,
          reason: 'Analyse automatique indisponible.',
          at: now,
        },
      })
      .eq('id', videoId);
    await logModeration(adminClient, {
      actor: 'system',
      targetType: 'video',
      targetId: videoId,
      action: 'ai_unavailable',
      reason: 'Analyse automatique indisponible : mise en file d\'attente.',
      metadata: { provider: provider.name },
    });
    return { status: 200, body: { status: 'pending_moderation' } };
  }

  if (verdict.verdict === 'clean' && verdict.confidence >= 60) {
    // PIÈGE : le trigger pose `published_at` automatiquement — SAUF pour
    // `service_role`, qu'il exempte dès sa première ligne. Sans cette valeur
    // explicite, le clip serait publié, visible par la RLS, mais ABSENT du fil
    // « Nouveautés » qui trie sur `published_at`. Panne silencieuse.
    await adminClient
      .from('videos')
      .update({
        status: 'published',
        published_at: now,
        moderation_result: {
          state: 'approved',
          provider: provider.name,
          confidence: verdict.confidence,
          at: now,
        },
      })
      .eq('id', videoId);
    await logModeration(adminClient, {
      actor: 'ai',
      targetType: 'video',
      targetId: videoId,
      action: 'video_published',
      metadata: { provider: provider.name, confidence: verdict.confidence },
    });
    return { status: 200, body: { status: 'published' } };
  }

  if (verdict.verdict === 'flagged' && verdict.confidence >= 70) {
    const reason = CATEGORY_REASONS[verdict.category] ?? CATEGORY_REASONS.none;
    await adminClient
      .from('videos')
      .update({
        status: 'rejected',
        moderation_result: {
          state: 'rejected',
          provider: provider.name,
          category: verdict.category,
          confidence: verdict.confidence,
          reason,
          at: now,
        },
      })
      .eq('id', videoId);
    await logModeration(adminClient, {
      actor: 'ai',
      targetType: 'video',
      targetId: videoId,
      action: 'reject_video',
      reason,
      metadata: { provider: provider.name, category: verdict.category },
    });
    return { status: 200, body: { status: 'rejected', reason } };
  }

  // Doute, ou confiance insuffisante pour trancher : file admin.
  await adminClient
    .from('videos')
    .update({
      moderation_result: {
        state: 'pending_admin',
        provider: provider.name,
        category: verdict.category,
        confidence: verdict.confidence,
        reason: 'Vérification humaine en cours.',
        at: now,
      },
    })
    .eq('id', videoId);
  await logModeration(adminClient, {
    actor: 'ai',
    targetType: 'video',
    targetId: videoId,
    action: 'video_queued',
    reason: 'Confiance insuffisante pour décider automatiquement.',
    metadata: { provider: provider.name, confidence: verdict.confidence },
  });
  return { status: 200, body: { status: 'pending_moderation' } };
}

/// Reprise planifiée : rien ne doit rester coincé.
async function requeue(
  adminClient: SupabaseClient,
): Promise<Record<string, unknown>> {
  const staleBefore = new Date(Date.now() - STALE_MINUTES * 60_000)
    .toISOString();
  const giveUpBefore = new Date(Date.now() - GIVE_UP_HOURS * 3600_000)
    .toISOString();

  // Abandon : au-delà de 24 h, on cesse d'analyser et on pousse dans la file
  // admin. Un humain décidera — c'est toujours mieux que l'oubli silencieux.
  const { data: abandoned } = await adminClient
    .from('videos')
    .update({
      status: 'pending_moderation',
      moderation_result: {
        state: 'pending_admin',
        reason: 'Vérification automatique impossible depuis 24 h.',
        at: new Date().toISOString(),
      },
    })
    .eq('status', 'processing')
    .lt('created_at', giveUpBefore)
    .select('id');

  const { data: stale } = await adminClient
    .from('videos')
    .select('id')
    .in('status', ['processing'])
    .lt('created_at', staleBefore)
    .gte('created_at', giveUpBefore)
    .limit(20);

  let retried = 0;
  for (const row of stale ?? []) {
    await moderateOne(adminClient, row.id as string, null);
    retried += 1;
  }
  return { retried, abandoned: abandoned?.length ?? 0 };
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
