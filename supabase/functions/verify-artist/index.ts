// Edge Function : verify-artist
//
// Reçoit une candidature d'artiste, analyse le dossier et la pièce d'identité,
// décide (docs/ARCHITECTURE.md §4), et promeut le rôle si la candidature est
// approuvée.
//
// C'est la zone la plus sensible du projet. Les décisions structurantes :
//
// 1. **Le document est téléversé par le client, directement dans le bucket
//    privé `identity-docs`.** Le corps d'une Edge Function est plafonné et le
//    base64 gonfle de 33 % ; faire transiter 5 Mo d'image par ici obligerait à
//    tout bufferiser en mémoire pour aucun gain. Le client possède déjà les
//    octets, il les a affichés en aperçu.
//
// 2. **Le chemin envoyé par le client n'est jamais utilisé tel quel.** On n'en
//    conserve que le nom de fichier et on recolle l'identifiant tiré du JWT.
//    Sans cela, il suffirait d'envoyer `<uid-de-quelqu-un-d-autre>/piece.jpg`
//    pour faire analyser — et faire purger — le document d'un tiers.
//
// 3. **La ligne de candidature naît ici, en `service_role`.** La table n'a
//    aucune politique INSERT : il est donc impossible qu'une candidature existe
//    sans qu'une analyse ait été déclenchée.
//
// 4. **Aucune donnée du document n'atteint la base.** Le schéma de réponse ne
//    comporte aucun champ capable de porter un numéro, une adresse ou une date
//    de naissance (voir `_shared/verification-rules.ts`). Trois barrières : le
//    schéma, l'interdiction explicite dans le prompt, et l'épuration par
//    expression régulière du seul champ libre. Ce qui est écrit en base provient
//    de l'objet **revalidé par Zod**, jamais de la réponse brute.
//
// 5. **Le rate limit autoritaire est ici, pas dans le trigger.** Le trigger SQL
//    s'exempte pour `service_role` — c'est-à-dire pour cette fonction. Le patron
//    « exempter service_role », qui protège partout ailleurs, désactiverait ici
//    la règle métier. Le trigger ne reste qu'un filet contre un INSERT direct.
//
// 6. **Le document est purgé immédiatement** dès qu'une décision finale tombe.
//    Le cron à 30 jours n'est qu'un filet pour les dossiers en revue manuelle.
//
// Déploiement (non exécuté automatiquement) :
//   supabase functions deploy verify-artist
// Secrets requis :
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
//   GEMINI_API_KEY  (ou DEEPSEEK_API_KEY / DEEPSEECK_API_KEY si AI_PROVIDER=deepseek)

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { z } from 'https://esm.sh/zod@3.23.8';

import { getAiProvider } from '../_shared/ai-provider.ts';
import {
  corsHeaders,
  jsonResponse,
  logModeration,
} from '../_shared/require-admin.ts';
import {
  type DossierAnalysis,
  dossierAnalysisSchema,
  decideApplication,
  type IdentityAnalysis,
  identityAnalysisSchema,
  sanitizeNotes,
} from '../_shared/verification-rules.ts';

const BUCKET = 'identity-docs';
const MAX_DOCUMENT_BYTES = 5 * 1024 * 1024;
const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp'];

const requestSchema = z.object({
  stageName: z.string().trim().min(2).max(60),
  links: z.array(z.string().trim().url().max(200)).max(5).default([]),
  statement: z.string().trim().min(30).max(2000),
  // Seul le nom de fichier compte ; le préfixe est reconstruit depuis le JWT.
  documentPath: z.string().min(1).max(200),
  // Le consentement est une exigence de l'architecture §4. Refuser sans lui.
  consent: z.literal(true),
}).strict();

/// Schémas JSON transmis au fournisseur d'IA. Volontairement fermés
/// (`additionalProperties: false`) et sans aucun champ de texte long.
const identityJsonSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'readable',
    'looks_tampered',
    'name_matches',
    'document_type_plausible',
    'confidence',
  ],
  properties: {
    readable: { type: 'boolean' },
    looks_tampered: { type: 'boolean' },
    name_matches: { type: 'boolean' },
    document_type_plausible: { type: 'boolean' },
    confidence: { type: 'integer', minimum: 0, maximum: 100 },
    notes: { type: 'string', maxLength: 160 },
  },
};

const dossierJsonSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['coherent', 'looks_spam', 'links_plausible', 'confidence'],
  properties: {
    coherent: { type: 'boolean' },
    looks_spam: { type: 'boolean' },
    links_plausible: { type: 'boolean' },
    confidence: { type: 'integer', minimum: 0, maximum: 100 },
    notes: { type: 'string', maxLength: 160 },
  },
};

function identityPrompt(fullName: string): string {
  return [
    'Tu vérifies une pièce d\'identité pour une plateforme musicale.',
    `Le nom civil attendu est : « ${fullName} ».`,
    '',
    'INTERDICTION ABSOLUE : ne recopie AUCUNE donnée figurant sur le document —',
    'ni numéro de pièce, ni adresse, ni date ou lieu de naissance, ni aucune',
    'autre mention. Le champ « notes » ne doit contenir aucune donnée',
    'personnelle : uniquement une remarque générale de qualité d\'image.',
    '',
    'Évalue uniquement :',
    '- readable : le document est-il net et lisible ?',
    '- document_type_plausible : ressemble-t-il à une pièce d\'identité officielle ?',
    '- name_matches : le nom porté correspond-il au nom civil attendu ci-dessus ?',
    '- looks_tampered : y a-t-il des signes visibles de retouche ou de montage ?',
    '- confidence : ta confiance globale dans cette analyse, de 0 à 100.',
    '',
    'Réponds uniquement selon le schéma JSON fourni.',
  ].join('\n');
}

function dossierPrompt(
  stageName: string,
  statement: string,
  links: string[],
): string {
  return [
    'Tu évalues le dossier de candidature d\'un artiste musical.',
    '',
    `Nom de scène : ${stageName}`,
    `Liens fournis : ${links.length > 0 ? links.join(', ') : 'aucun'}`,
    `Présentation : ${statement}`,
    '',
    'Évalue :',
    '- coherent : la présentation est-elle cohérente avec une activité musicale ?',
    '- looks_spam : le texte ressemble-t-il à du remplissage, du spam ou du contenu généré sans rapport ?',
    '- links_plausible : les liens ressemblent-ils à des profils musicaux crédibles ?',
    '- confidence : ta confiance globale, de 0 à 100.',
    '',
    'Réponds uniquement selon le schéma JSON fourni.',
  ].join('\n');
}

/// Vérifie la signature réelle du fichier plutôt que le type déclaré.
///
/// Le bucket filtre déjà par `allowed_mime_types`, mais ce filtre porte sur
/// l'en-tête annoncé au téléversement, que le client choisit librement.
function sniffMime(bytes: Uint8Array): string | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
    bytes[3] === 0x47
  ) {
    return 'image/png';
  }
  const riff = String.fromCharCode(...bytes.subarray(0, 4));
  const webp = String.fromCharCode(...bytes.subarray(8, 12));
  if (riff === 'RIFF' && webp === 'WEBP') return 'image/webp';
  return null;
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

  // Le chemin est RECONSTRUIT, jamais repris tel quel (voir en-tête, point 2).
  const fileName = input.documentPath.split('/').pop() ?? '';
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(fileName)) {
    return jsonResponse({ error: 'Document invalide.' }, 400);
  }
  const documentPath = `${user.id}/${fileName}`;

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
        id_document_path: documentPath,
        status: 'pending',
      })
      .select('id')
      .single();
    if (insertError || !application) {
      console.error('verify-artist: insertion impossible', insertError);
      return jsonResponse({ error: 'La candidature n\'a pas pu être enregistrée.' }, 500);
    }
    const applicationId = application.id as string;

    // ── Analyse ─────────────────────────────────────────────────────────────
    const provider = getAiProvider();
    let identity: IdentityAnalysis | null = null;
    let dossier: DossierAnalysis | null = null;
    let degraded = false;
    let blocked = false;

    // Identité civile : lue en `service_role`. `user_identities` n'a
    // volontairement aucune politique admin — c'est exactement pour ce chemin
    // que la Phase 3.5 l'a laissée fermée.
    const { data: civil } = await adminClient
      .from('user_identities')
      .select('legal_first_name, legal_last_name')
      .eq('user_id', user.id)
      .maybeSingle();
    const hasCivilIdentity = Boolean(
      civil?.legal_first_name && civil?.legal_last_name,
    );

    if (!provider.supportsImages) {
      // DeepSeek : pas de vision. La vérification d'identité est impossible,
      // donc revue manuelle — comportement prescrit par l'architecture §2.
      degraded = true;
    } else if (hasCivilIdentity) {
      const { data: blob, error: downloadError } = await adminClient.storage
        .from(BUCKET)
        .download(documentPath);
      if (downloadError || !blob) {
        console.error('verify-artist: document illisible', downloadError);
        degraded = true;
      } else {
        const bytes = new Uint8Array(await blob.arrayBuffer());
        const realMime = sniffMime(bytes);
        if (
          bytes.length > MAX_DOCUMENT_BYTES ||
          realMime === null ||
          !ALLOWED_MIME.includes(realMime)
        ) {
          // Fichier qui n'est pas l'image annoncée : on ne l'envoie nulle part.
          await adminClient.storage.from(BUCKET).remove([documentPath]);
          await adminClient
            .from('artist_applications')
            .update({
              status: 'rejected',
              decision_reason:
                'Le fichier fourni n\'est pas une image valide. Recandidate avec une photo au format JPEG, PNG ou WebP.',
              decided_at: new Date().toISOString(),
              id_document_path: null,
              document_purged_at: new Date().toISOString(),
            })
            .eq('id', applicationId);
          return jsonResponse({ status: 'rejected' }, 200);
        }

        const fullName =
          `${civil!.legal_first_name} ${civil!.legal_last_name}`.trim();
        const result = await provider.analyzeImage(
          identityPrompt(fullName),
          { bytes, mimeType: realMime },
          identityJsonSchema,
        );
        if (result.ok) {
          const validated = identityAnalysisSchema.safeParse(result.data);
          if (validated.success) {
            identity = validated.data;
          } else {
            degraded = true;
          }
        } else if (result.kind === 'blocked') {
          blocked = true;
        } else {
          degraded = true;
        }
      }
    }

    const dossierResult = await provider.analyzeText(
      dossierPrompt(input.stageName, input.statement, input.links),
      dossierJsonSchema,
    );
    if (dossierResult.ok) {
      const validated = dossierAnalysisSchema.safeParse(dossierResult.data);
      if (validated.success) dossier = validated.data;
    }

    const decision = decideApplication({
      identity,
      dossier,
      hasCivilIdentity,
      degraded,
      blocked,
    });

    // ── Écriture du verdict ─────────────────────────────────────────────────
    //
    // `ai_analysis` est reconstruit champ par champ depuis les objets validés
    // par Zod : la réponse brute du modèle n'est jamais sérialisée en base.
    // C'est la barrière qui garantit qu'aucun champ inattendu — donc aucune
    // transcription de document — n'y atterrit.
    const aiAnalysis: Record<string, unknown> = {
      degraded,
      blocked,
      has_civil_identity: hasCivilIdentity,
    };
    if (identity) {
      aiAnalysis.identity = {
        readable: identity.readable,
        looks_tampered: identity.looks_tampered,
        name_matches: identity.name_matches,
        document_type_plausible: identity.document_type_plausible,
        confidence: identity.confidence,
        notes: sanitizeNotes(identity.notes) ?? null,
      };
    }
    if (dossier) {
      aiAnalysis.dossier = {
        coherent: dossier.coherent,
        looks_spam: dossier.looks_spam,
        links_plausible: dossier.links_plausible,
        confidence: dossier.confidence,
        notes: sanitizeNotes(dossier.notes) ?? null,
      };
    }

    const isFinal = decision.status === 'approved' ||
      decision.status === 'rejected';
    const now = new Date().toISOString();

    const update: Record<string, unknown> = {
      status: decision.status,
      ai_score: decision.score,
      ai_analysis: aiAnalysis,
      ai_provider: provider.name,
      decision_reason: decision.reason,
    };
    if (isFinal) update.decided_at = now;

    await adminClient
      .from('artist_applications')
      .update(update)
      .eq('id', applicationId);

    // Promotion : seule voie possible. `prevent_role_escalation()` refuse tout
    // changement de rôle qui ne vient pas de `service_role`.
    if (decision.status === 'approved') {
      const { error: roleError } = await adminClient
        .from('profiles')
        .update({ role: 'artist' })
        .eq('id', user.id);
      if (roleError) {
        console.error('verify-artist: promotion impossible', roleError);
        // La candidature retombe en revue manuelle : l'utilisateur ne doit pas
        // rester avec un « approuvé » qui ne lui donne aucun droit.
        await adminClient
          .from('artist_applications')
          .update({
            status: 'manual_review',
            decided_at: null,
            decision_reason:
              'Validation en cours de finalisation par l\'équipe.',
          })
          .eq('id', applicationId);
        await logModeration(adminClient, {
          actor: 'system',
          targetType: 'application',
          targetId: applicationId,
          action: 'promotion_failed',
          reason: String(roleError.message ?? roleError),
        });
        return jsonResponse({ status: 'manual_review' }, 200);
      }
    }

    await logModeration(adminClient, {
      actor: degraded || blocked ? 'system' : 'ai',
      targetType: 'application',
      targetId: applicationId,
      action: degraded || blocked
        ? 'ai_unavailable'
        : `application_${decision.status}`,
      reason: decision.reason,
      metadata: {
        provider: provider.name,
        model: provider.model,
        score: decision.score,
      },
    });

    // Purge immédiate sur décision finale. Le cron à 30 jours n'est qu'un filet
    // pour les dossiers restés en revue manuelle.
    if (isFinal) {
      const { error: removeError } = await adminClient.storage
        .from(BUCKET)
        .remove([documentPath]);
      if (removeError) {
        console.error('verify-artist: purge impossible', removeError);
      } else {
        await adminClient
          .from('artist_applications')
          .update({ id_document_path: null, document_purged_at: now })
          .eq('id', applicationId);
      }
    }

    // Le score n'est renvoyé au candidat sur AUCUN chemin : lui apprendre où il
    // se situe par rapport au seuil, c'est lui apprendre comment le franchir.
    return jsonResponse(
      { status: decision.status, reason: decision.reason },
      200,
    );
  } catch (error) {
    console.error('verify-artist: erreur inattendue', error);
    return jsonResponse({ error: 'La candidature n\'a pas pu être traitée.' }, 500);
  }
});
