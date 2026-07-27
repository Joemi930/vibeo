// Règles de décision d'une candidature d'artiste (docs/ARCHITECTURE.md §4).
//
// Tout ce fichier est **pur** : aucune entrée/sortie, aucun accès réseau, aucun
// client Supabase. C'est délibéré et c'est ce qui rend les seuils 80/30
// réellement testables — sans quoi on ne peut vérifier une frontière de
// décision qu'en appelant un vrai service d'IA, donc jamais.
//
// Y toucher sans mettre à jour `tests/verification_rules_test.ts` est une
// erreur : ces règles décident de l'accès au statut d'artiste sur la foi d'une
// pièce d'identité.

import { z } from 'https://esm.sh/zod@3.23.8';

/// Analyse du document d'identité.
///
/// Le schéma ne comporte **aucun champ capable de porter un numéro, une adresse
/// ou une date de naissance**. Ce n'est pas une précaution de style : c'est la
/// garantie structurelle que rien du contenu du document n'atteint la base
/// (règle CLAUDE.md n°5). Ne jamais y ajouter de champ libre supplémentaire.
export const identityAnalysisSchema = z.object({
  readable: z.boolean(),
  looks_tampered: z.boolean(),
  name_matches: z.boolean(),
  document_type_plausible: z.boolean(),
  confidence: z.number().int().min(0).max(100),
  notes: z.string().max(160).optional(),
}).strict();

export type IdentityAnalysis = z.infer<typeof identityAnalysisSchema>;

/// Analyse du dossier textuel (nom de scène, liens, présentation).
export const dossierAnalysisSchema = z.object({
  coherent: z.boolean(),
  looks_spam: z.boolean(),
  links_plausible: z.boolean(),
  confidence: z.number().int().min(0).max(100),
  notes: z.string().max(160).optional(),
}).strict();

export type DossierAnalysis = z.infer<typeof dossierAnalysisSchema>;

export type ApplicationDecision = {
  status: 'approved' | 'rejected' | 'manual_review';
  score: number | null;
  reason: string;
};

/// Seuils de l'architecture §4. Constantes nommées pour qu'un test échoue si
/// quelqu'un les déplace par inadvertance.
export const APPROVE_THRESHOLD = 80;
export const REJECT_THRESHOLD = 30;

export type DecisionInput = {
  /// `null` = analyse indisponible (quota, panne, sortie invalide).
  identity: IdentityAnalysis | null;
  dossier: DossierAnalysis | null;
  /// L'utilisateur a-t-il renseigné son identité civile ? Sans elle, il n'y a
  /// rien à quoi comparer le document.
  hasCivilIdentity: boolean;
  /// L'IA n'a pas rendu de verdict exploitable, quelle qu'en soit la raison.
  degraded: boolean;
  /// Le fournisseur a refusé d'analyser (filtre de sécurité). À distinguer d'un
  /// document réellement illisible.
  blocked: boolean;
};

/// Décide du sort d'une candidature.
///
/// Principe directeur : **une analyse dégradée n'est jamais une décision.**
/// Quota épuisé, panne réseau, sortie invalide, fournisseur sans vision — tout
/// cela mène à la revue manuelle, jamais à une approbation ni à un rejet
/// automatiques. C'est le seul comportement défendable quand la donnée d'entrée
/// est une pièce d'identité : le pire résultat acceptable est de faire attendre
/// quelqu'un, pas de lui refuser son identité à cause d'une panne.
export function decideApplication(input: DecisionInput): ApplicationDecision {
  const { identity, dossier, hasCivilIdentity, degraded, blocked } = input;

  // 1. Rien d'exploitable → l'humain tranche.
  if (blocked) {
    return {
      status: 'manual_review',
      score: null,
      reason:
        'Le document n\'a pas pu être analysé automatiquement. Un membre de l\'équipe va le vérifier.',
    };
  }
  if (degraded || identity === null) {
    return {
      status: 'manual_review',
      score: null,
      reason:
        'La vérification automatique est momentanément indisponible. Ta candidature sera examinée manuellement.',
    };
  }
  if (!hasCivilIdentity) {
    return {
      status: 'manual_review',
      score: null,
      reason:
        'Ton identité civile n\'est pas renseignée : la correspondance avec le document ne peut pas être vérifiée automatiquement.',
    };
  }

  // 2. Document inexploitable. Distinct du cas `blocked` ci-dessus : ici l'IA a
  //    bien regardé le document et le juge illisible.
  if (!identity.readable) {
    return {
      status: 'rejected',
      score: null,
      reason:
        'Le document fourni est illisible. Tu peux recandidater avec une photo plus nette.',
    };
  }

  // 3. Signes de falsification : rejet, sans détailler ce qui a été repéré —
  //    expliquer précisément reviendrait à publier le mode d'emploi.
  if (identity.looks_tampered || !identity.document_type_plausible) {
    return {
      status: 'rejected',
      score: null,
      reason:
        'Le document fourni ne permet pas de valider ton identité. Contacte l\'équipe si tu penses qu\'il s\'agit d\'une erreur.',
    };
  }

  // 4. Score composite. Le document pèse plus que le dossier : c'est lui qui
  //    porte la preuve d'identité, le dossier n'est qu'un faisceau d'indices.
  const dossierConfidence = dossier?.confidence ?? 0;
  let score = 0.6 * identity.confidence + 0.4 * dossierConfidence;
  if (!identity.name_matches) score -= 40;
  if (dossier?.looks_spam === true) score -= 20;
  score = Math.max(0, Math.min(100, Math.round(score * 100) / 100));

  // 5. Un dossier sans analyse textuelle ne peut pas atteindre l'approbation
  //    automatique : il manque la moitié de l'information.
  if (dossier === null) {
    return {
      status: 'manual_review',
      score,
      reason:
        'Ton dossier n\'a pas pu être analysé automatiquement. Il sera examiné manuellement.',
    };
  }

  if (score >= APPROVE_THRESHOLD && identity.name_matches) {
    return {
      status: 'approved',
      score,
      reason: 'Candidature validée. Bienvenue parmi les artistes Vibeo.',
    };
  }

  if (score <= REJECT_THRESHOLD) {
    return {
      status: 'rejected',
      score,
      reason:
        'Ta candidature n\'a pas pu être validée. Tu peux recandidater dans une semaine avec un dossier plus complet.',
    };
  }

  return {
    status: 'manual_review',
    score,
    reason:
      'Ta candidature demande une vérification humaine. Nous revenons vers toi rapidement.',
  };
}

/// Retire d'un champ libre toute suite de chiffres susceptible de provenir du
/// document (numéro de pièce, date de naissance, code postal…).
///
/// Le prompt interdit déjà au modèle de recopier quoi que ce soit, et le schéma
/// ne prévoit aucun champ pour le faire. Ceci est la troisième barrière : les
/// deux premières reposent sur l'obéissance du modèle, celle-ci non.
export function sanitizeNotes(notes: string | undefined): string | undefined {
  if (!notes) return undefined;
  const cleaned = notes
    // Suites de 4 chiffres ou plus, éventuellement séparées par / - . ou espace.
    .replace(/\d[\d\s./-]{3,}\d/g, '…')
    .replace(/\d{4,}/g, '…')
    .trim();
  return cleaned.length === 0 ? undefined : cleaned.slice(0, 160);
}
