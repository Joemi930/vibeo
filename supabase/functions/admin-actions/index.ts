// Edge Function : admin-actions
//
// Point d'entrée unique de toutes les actions d'administration. Une seule
// fonction plutôt que quatre : elles partagent exactement la même garde, les
// mêmes en-têtes et le même journal ; les éclater multiplierait les endroits où
// oublier une vérification, pour aucun bénéfice.
//
// ── Pourquoi ces actions ne peuvent PAS passer par le client Supabase
//
// Le trigger `videos_guard_client_fields()` interdit les statuts `rejected` et
// `removed` à tout rôle autre que `service_role`. Or **un administrateur
// connecté est `authenticated`, pas `service_role`**. Ajouter une politique
// `videos_update_admin` ne servirait donc à rien : elle serait incapable de
// faire la seule chose pour laquelle elle existerait. De même,
// `prevent_role_escalation()` interdit toute modification de `profiles.role`
// hors `service_role`.
//
// Conséquence : la RLS suffit à ce que l'admin *lise* ses files d'attente, mais
// toute *action* passe obligatoirement par ici.
//
// ── La garde
//
// `requireAdmin` relit `profiles.role` dans la base avec la clé `service_role`.
// Jamais depuis une revendication du jeton (un admin rétrogradé présente encore
// un JWT valide jusqu'à expiration), jamais depuis le corps de la requête.
//
// Déploiement :  supabase functions deploy admin-actions
// Secrets :      SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { z } from 'https://esm.sh/zod@3.23.8';

import {
  corsHeaders,
  jsonResponse,
  logModeration,
  requireAdmin,
} from '../_shared/require-admin.ts';

/// Durée de vie d'une URL de document d'identité. Cinq minutes, comme l'exige
/// l'architecture §4 : assez pour examiner, trop peu pour partager.
const DOCUMENT_URL_TTL_SECONDS = 300;

const requestSchema = z.discriminatedUnion('action', [
  z.object({
    action: z.literal('decide_application'),
    applicationId: z.string().uuid(),
    decision: z.enum(['approved', 'rejected']),
    reason: z.string().trim().min(3).max(500),
  }).strict(),
  z.object({
    action: z.literal('document_url'),
    applicationId: z.string().uuid(),
  }).strict(),
  z.object({
    action: z.literal('moderate_video'),
    videoId: z.string().uuid(),
    decision: z.enum(['published', 'rejected', 'removed']),
    reason: z.string().trim().max(500).optional(),
  }).strict(),
  z.object({
    action: z.literal('resolve_report'),
    reportId: z.string().uuid(),
    resolution: z.enum(['remove_content', 'warn_author', 'dismiss']),
    reason: z.string().trim().max(500).optional(),
  }).strict(),
  z.object({
    action: z.literal('change_user_role'),
    userId: z.string().uuid(),
    role: z.enum(['listener', 'artist', 'admin']),
  }).strict(),
  z.object({
    action: z.literal('delete_user'),
    userId: z.string().uuid(),
    reason: z.string().trim().max(500).optional(),
  }).strict(),
]);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Méthode non supportée.' }, 405);
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

  const guard = await requireAdmin(req);
  if (!guard.ok) return guard.response;
  const { adminClient, adminId } = guard.ctx;

  const now = new Date().toISOString();
  const body = parsed.data;

  try {
    switch (body.action) {
      // ── Candidature d'artiste ────────────────────────────────────────────
      case 'decide_application': {
        const { data: application } = await adminClient
          .from('artist_applications')
          .select('id, user_id, status, id_document_path')
          .eq('id', body.applicationId)
          .maybeSingle();
        if (!application) {
          return jsonResponse({ error: 'Candidature introuvable.' }, 404);
        }
        if (
          application.status !== 'pending' &&
          application.status !== 'manual_review'
        ) {
          return jsonResponse({ error: 'Candidature déjà traitée.' }, 409);
        }

        if (body.decision === 'approved') {
          const { error: roleError } = await adminClient
            .from('profiles')
            .update({ role: 'artist' })
            .eq('id', application.user_id);
          if (roleError) {
            console.error('admin-actions: promotion impossible', roleError);
            return jsonResponse({ error: 'La promotion a échoué.' }, 500);
          }
        }

        await adminClient
          .from('artist_applications')
          .update({
            status: body.decision,
            decision_reason: body.reason,
            reviewed_by: adminId,
            decided_at: now,
          })
          .eq('id', body.applicationId);

        // Purge du document dès la décision : l'architecture §4 impose la
        // minimisation, et le cron à 30 jours n'est qu'un filet de rattrapage.
        // On ne marque `document_purged_at` que si la suppression a réellement
        // réussi — une trace mensongère serait pire que pas de trace.
        if (application.id_document_path) {
          const { error: removeError } = await adminClient.storage
            .from('identity-docs')
            .remove([application.id_document_path as string]);
          if (!removeError) {
            await adminClient
              .from('artist_applications')
              .update({ id_document_path: null, document_purged_at: now })
              .eq('id', body.applicationId);
          } else {
            console.error('admin-actions: purge impossible', removeError);
          }
        }

        await logModeration(adminClient, {
          actor: 'admin',
          actorId: adminId,
          targetType: 'application',
          targetId: body.applicationId,
          action: `application_${body.decision}`,
          reason: body.reason,
        });
        return jsonResponse({ status: body.decision }, 200);
      }

      // ── Visionneuse sécurisée du document ────────────────────────────────
      case 'document_url': {
        const { data: application } = await adminClient
          .from('artist_applications')
          .select('id_document_path')
          .eq('id', body.applicationId)
          .maybeSingle();
        const path = application?.id_document_path as string | null;
        if (!path) {
          return jsonResponse(
            { error: 'Aucun document disponible (déjà supprimé).' },
            404,
          );
        }

        const { data: signed, error: signError } = await adminClient.storage
          .from('identity-docs')
          .createSignedUrl(path, DOCUMENT_URL_TTL_SECONDS);
        if (signError || !signed) {
          console.error('admin-actions: signature impossible', signError);
          return jsonResponse({ error: 'Document indisponible.' }, 500);
        }

        // Chaque consultation d'une pièce d'identité laisse une trace nominative.
        // C'est la contrepartie du fait que le bucket n'a AUCUNE politique de
        // lecture : le seul chemin d'accès est audité.
        await logModeration(adminClient, {
          actor: 'admin',
          actorId: adminId,
          targetType: 'application',
          targetId: body.applicationId,
          action: 'identity_document_viewed',
          metadata: { ttl_seconds: DOCUMENT_URL_TTL_SECONDS },
        });

        return jsonResponse(
          { url: signed.signedUrl, expiresIn: DOCUMENT_URL_TTL_SECONDS },
          200,
        );
      }

      // ── Modération d'un clip ─────────────────────────────────────────────
      case 'moderate_video': {
        const { data: video } = await adminClient
          .from('videos')
          .select('id, status')
          .eq('id', body.videoId)
          .maybeSingle();
        if (!video) return jsonResponse({ error: 'Clip introuvable.' }, 404);

        const update: Record<string, unknown> = {
          status: body.decision,
          moderation_result: {
            state: body.decision,
            by: 'admin',
            reason: body.reason ?? null,
            at: now,
          },
        };
        // Même piège que dans `moderate-video` : le trigger n'alimente pas
        // `published_at` pour `service_role`. Sans cette ligne, un clip
        // republié par un admin n'apparaîtrait jamais dans « Nouveautés ».
        if (body.decision === 'published') update.published_at = now;

        await adminClient.from('videos').update(update).eq('id', body.videoId);
        await logModeration(adminClient, {
          actor: 'admin',
          actorId: adminId,
          targetType: 'video',
          targetId: body.videoId,
          action: body.decision === 'published'
            ? 'video_published'
            : body.decision === 'rejected'
            ? 'reject_video'
            : 'remove_video',
          reason: body.reason ?? null,
        });
        return jsonResponse({ status: body.decision }, 200);
      }

      // ── Traitement d'un signalement ──────────────────────────────────────
      case 'resolve_report': {
        const { data: report } = await adminClient
          .from('reports')
          .select('id, status, video_id, comment_id, target_kind, target_author_id')
          .eq('id', body.reportId)
          .maybeSingle();
        if (!report) {
          return jsonResponse({ error: 'Signalement introuvable.' }, 404);
        }
        if (report.status !== 'pending') {
          return jsonResponse({ error: 'Signalement déjà traité.' }, 409);
        }

        if (body.resolution === 'remove_content') {
          if (report.target_kind === 'video' && report.video_id) {
            await adminClient
              .from('videos')
              .update({
                status: 'removed',
                moderation_result: {
                  state: 'removed',
                  by: 'admin',
                  reason: body.reason ?? 'Retiré suite à un signalement.',
                  at: now,
                },
              })
              .eq('id', report.video_id);
          } else if (report.target_kind === 'comment' && report.comment_id) {
            // Suppression douce : la ligne survit, ce qui préserve le fil de
            // discussion et la trace du signalement.
            await adminClient
              .from('comments')
              .update({ deleted_at: now })
              .eq('id', report.comment_id);
          }
        }

        // `status` reste dans l'énumération existante (`reviewed`/`dismissed`).
        // La nature exacte de l'action vit au journal — c'est ce qui a évité
        // d'ajouter une valeur `actioned` à l'énumération, opération qui ne
        // passe pas dans une migration transactionnelle.
        await adminClient
          .from('reports')
          .update({
            status: body.resolution === 'dismiss' ? 'dismissed' : 'reviewed',
            reviewed_by: adminId,
            reviewed_at: now,
          })
          .eq('id', body.reportId);

        await logModeration(adminClient, {
          actor: 'admin',
          actorId: adminId,
          targetType: 'report',
          targetId: body.reportId,
          action: body.resolution === 'remove_content'
            ? (report.target_kind === 'video'
              ? 'remove_video'
              : 'remove_comment')
            : body.resolution === 'warn_author'
            ? 'warn_author'
            : 'report_dismissed',
          reason: body.reason ?? null,
          metadata: { target_author_id: report.target_author_id },
        });
        return jsonResponse({ status: 'ok' }, 200);
      }

      // ── Gestion des utilisateurs ──────────────────────────────────────────
      case 'change_user_role': {
        if (body.userId === adminId) {
          return jsonResponse(
            { error: 'Tu ne peux pas modifier ton propre rôle.' },
            400,
          );
        }

        const { error: roleError } = await adminClient
          .from('profiles')
          .update({ role: body.role })
          .eq('id', body.userId);
        if (roleError) {
          console.error('admin-actions: changement de rôle impossible', roleError);
          return jsonResponse({ error: 'Le changement de rôle a échoué.' }, 500);
        }

        await logModeration(adminClient, {
          actor: 'admin',
          actorId: adminId,
          targetType: 'user',
          targetId: body.userId,
          action: `role_changed_to_${body.role}`,
          reason: `Rôle changé en ${body.role} par l'admin.`,
        });
        return jsonResponse({ status: 'ok', role: body.role }, 200);
      }

      case 'delete_user': {
        if (body.userId === adminId) {
          return jsonResponse(
            { error: 'Tu ne peux pas supprimer ton propre compte.' },
            400,
          );
        }

        // La suppression d'un auth.users cascade vers profiles (on delete
        // cascade), donc une seule requête suffit.
        const { error: deleteError } = await adminClient.auth.admin
          .deleteUser(body.userId);
        if (deleteError) {
          console.error('admin-actions: suppression impossible', deleteError);
          return jsonResponse({ error: 'La suppression a échoué.' }, 500);
        }

        await logModeration(adminClient, {
          actor: 'admin',
          actorId: adminId,
          targetType: 'user',
          targetId: body.userId,
          action: 'user_deleted',
          reason: body.reason ?? 'Compte supprimé par l\'administration.',
        });
        return jsonResponse({ status: 'deleted' }, 200);
      }
    }
  } catch (error) {
    console.error('admin-actions: erreur inattendue', error);
    return jsonResponse({ error: 'L\'action a échoué.' }, 500);
  }
});
