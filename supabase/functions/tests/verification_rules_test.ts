// Tests des règles de décision d'une candidature d'artiste.
//
// Lancement :  deno test --allow-net supabase/functions/tests/
//
// Aucun appel réseau, aucune clé, aucun fournisseur d'IA réel — c'est
// précisément l'intérêt d'avoir extrait `decideApplication` en fonction pure :
// les seuils 80/30 de l'architecture §4 sont vérifiables sans rien contacter.

import {
  assertEquals,
  assertNotEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';

import {
  APPROVE_THRESHOLD,
  decideApplication,
  type DossierAnalysis,
  dossierAnalysisSchema,
  type IdentityAnalysis,
  identityAnalysisSchema,
  REJECT_THRESHOLD,
  sanitizeNotes,
} from '../_shared/verification-rules.ts';

function identity(overrides: Partial<IdentityAnalysis> = {}): IdentityAnalysis {
  return {
    readable: true,
    looks_tampered: false,
    name_matches: true,
    document_type_plausible: true,
    confidence: 90,
    ...overrides,
  };
}

function dossier(overrides: Partial<DossierAnalysis> = {}): DossierAnalysis {
  return {
    coherent: true,
    looks_spam: false,
    links_plausible: true,
    confidence: 80,
    ...overrides,
  };
}

function decide(overrides: Record<string, unknown> = {}) {
  return decideApplication({
    identity: identity(),
    dossier: dossier(),
    hasCivilIdentity: true,
    degraded: false,
    blocked: false,
    ...overrides,
  } as Parameters<typeof decideApplication>[0]);
}

// ── Les seuils eux-mêmes ────────────────────────────────────────────────────

Deno.test('les seuils de l\'architecture sont bien 80 et 30', () => {
  assertEquals(APPROVE_THRESHOLD, 80);
  assertEquals(REJECT_THRESHOLD, 30);
});

Deno.test('un dossier excellent est approuvé automatiquement', () => {
  // 0.6×100 + 0.4×100 = 100
  const result = decide({
    identity: identity({ confidence: 100 }),
    dossier: dossier({ confidence: 100 }),
  });
  assertEquals(result.status, 'approved');
  assertEquals(result.score, 100);
});

Deno.test('exactement 80 approuve (la frontière est inclusive)', () => {
  // 0.6×80 + 0.4×80 = 80
  const result = decide({
    identity: identity({ confidence: 80 }),
    dossier: dossier({ confidence: 80 }),
  });
  assertEquals(result.score, 80);
  assertEquals(result.status, 'approved');
});

Deno.test('juste en dessous de 80 part en revue manuelle', () => {
  // 0.6×79 + 0.4×79 = 79
  const result = decide({
    identity: identity({ confidence: 79 }),
    dossier: dossier({ confidence: 79 }),
  });
  assertEquals(result.score, 79);
  assertEquals(result.status, 'manual_review');
});

Deno.test('exactement 30 rejette (la frontière est inclusive)', () => {
  const result = decide({
    identity: identity({ confidence: 30 }),
    dossier: dossier({ confidence: 30 }),
  });
  assertEquals(result.score, 30);
  assertEquals(result.status, 'rejected');
});

Deno.test('juste au-dessus de 30 part en revue manuelle', () => {
  const result = decide({
    identity: identity({ confidence: 31 }),
    dossier: dossier({ confidence: 31 }),
  });
  assertEquals(result.score, 31);
  assertEquals(result.status, 'manual_review');
});

// ── Le principe cardinal : une panne n'est jamais une décision ──────────────

Deno.test('analyse dégradée → revue manuelle, jamais un rejet', () => {
  const result = decide({ degraded: true, identity: null });
  assertEquals(result.status, 'manual_review');
  assertEquals(result.score, null);
});

Deno.test('quota épuisé ne peut pas approuver non plus', () => {
  // Même avec un dossier parfait par ailleurs : sans analyse d'identité, on ne
  // décide pas. C'est la règle qui protège contre une approbation en aveugle.
  const result = decide({
    degraded: true,
    identity: null,
    dossier: dossier({ confidence: 100 }),
  });
  assertNotEquals(result.status, 'approved');
  assertEquals(result.status, 'manual_review');
});

Deno.test('document bloqué par le filtre de sécurité → revue manuelle', () => {
  // Une photo de pièce d'identité déclenche parfois le filtre du fournisseur.
  // Ce n'est PAS un indice de fraude : le traiter comme tel rejetterait des
  // candidats honnêtes.
  const result = decide({ blocked: true, identity: null });
  assertEquals(result.status, 'manual_review');
});

Deno.test('le blocage prime sur le dégradé (message plus précis)', () => {
  const result = decide({ blocked: true, degraded: true, identity: null });
  assertEquals(result.status, 'manual_review');
});

Deno.test('identité civile absente → revue manuelle', () => {
  // Il n'y a rien à quoi comparer le document.
  const result = decide({ hasCivilIdentity: false });
  assertEquals(result.status, 'manual_review');
  assertEquals(result.score, null);
});

Deno.test('dossier non analysé → pas d\'approbation automatique', () => {
  const result = decide({
    identity: identity({ confidence: 100 }),
    dossier: null,
  });
  assertEquals(result.status, 'manual_review');
});

// ── Rejets légitimes ────────────────────────────────────────────────────────

Deno.test('document illisible → rejet', () => {
  const result = decide({ identity: identity({ readable: false }) });
  assertEquals(result.status, 'rejected');
});

Deno.test('document retouché → rejet, même avec une confiance élevée', () => {
  const result = decide({
    identity: identity({ looks_tampered: true, confidence: 100 }),
    dossier: dossier({ confidence: 100 }),
  });
  assertEquals(result.status, 'rejected');
});

Deno.test('type de document invraisemblable → rejet', () => {
  const result = decide({
    identity: identity({ document_type_plausible: false }),
  });
  assertEquals(result.status, 'rejected');
});

Deno.test('le motif de rejet n\'explique jamais ce qui a été repéré', () => {
  const result = decide({ identity: identity({ looks_tampered: true }) });
  const lowered = result.reason.toLowerCase();
  // Dire au fraudeur ce qui l'a trahi, c'est lui livrer le mode d'emploi.
  for (const leak of ['retouch', 'falsif', 'montage', 'trafiqu']) {
    assertEquals(lowered.includes(leak), false, `le motif fuite « ${leak} »`);
  }
});

// ── Nom non concordant ──────────────────────────────────────────────────────

Deno.test('nom non concordant : malus de 40 et jamais d\'approbation', () => {
  // Sans malus : 0.6×100 + 0.4×100 = 100, donc approuvé.
  const result = decide({
    identity: identity({ confidence: 100, name_matches: false }),
    dossier: dossier({ confidence: 100 }),
  });
  assertEquals(result.score, 60);
  assertEquals(result.status, 'manual_review');
});

Deno.test('nom non concordant bloque l\'approbation même à score élevé', () => {
  // Cas limite : le score reste ≥ 80 après le malus. La règle doit tout de
  // même refuser l'approbation automatique — le nom est le cœur du contrôle.
  const result = decide({
    identity: identity({ confidence: 100, name_matches: false }),
    dossier: dossier({ confidence: 100, looks_spam: false }),
  });
  assertNotEquals(result.status, 'approved');
});

Deno.test('dossier ressemblant à du spam : malus de 20', () => {
  const result = decide({
    identity: identity({ confidence: 100 }),
    dossier: dossier({ confidence: 100, looks_spam: true }),
  });
  assertEquals(result.score, 80);
});

Deno.test('le score reste borné à [0, 100]', () => {
  const result = decide({
    identity: identity({ confidence: 0, name_matches: false }),
    dossier: dossier({ confidence: 0, looks_spam: true }),
  });
  assertEquals(result.score, 0);
  assertEquals(result.status, 'rejected');
});

// ── Validation Zod : sorties malformées ─────────────────────────────────────

Deno.test('un objet vide est refusé par le schéma d\'identité', () => {
  assertEquals(identityAnalysisSchema.safeParse({}).success, false);
});

Deno.test('une confiance à 150 est refusée', () => {
  assertEquals(
    identityAnalysisSchema.safeParse({ ...identity(), confidence: 150 }).success,
    false,
  );
});

Deno.test('une confiance négative est refusée', () => {
  assertEquals(
    identityAnalysisSchema.safeParse({ ...identity(), confidence: -1 }).success,
    false,
  );
});

Deno.test('un champ surnuméraire est refusé (schéma fermé)', () => {
  // C'est la barrière structurelle contre l'arrivée en base d'une donnée du
  // document : le modèle ne peut pas ajouter de champ à sa guise.
  const result = identityAnalysisSchema.safeParse({
    ...identity(),
    document_number: 'AB123456',
  });
  assertEquals(result.success, false);
});

Deno.test('des notes de plus de 160 caractères sont refusées', () => {
  const result = identityAnalysisSchema.safeParse({
    ...identity(),
    notes: 'a'.repeat(161),
  });
  assertEquals(result.success, false);
});

Deno.test('le schéma du dossier refuse lui aussi les champs surnuméraires', () => {
  assertEquals(
    dossierAnalysisSchema.safeParse({ ...dossier(), extra: 1 }).success,
    false,
  );
});

// ── Épuration du champ libre ────────────────────────────────────────────────

Deno.test('un numéro de pièce est épuré des notes', () => {
  const cleaned = sanitizeNotes('Document net, numéro AB123456 visible.');
  assertEquals(cleaned?.includes('123456'), false);
});

Deno.test('une date de naissance est épurée', () => {
  const cleaned = sanitizeNotes('Né le 12/03/1990 selon le document.');
  assertEquals(cleaned?.includes('1990'), false);
  assertEquals(cleaned?.includes('12/03'), false);
});

Deno.test('un code postal est épuré', () => {
  const cleaned = sanitizeNotes('Adresse 75015 Paris');
  assertEquals(cleaned?.includes('75015'), false);
});

Deno.test('une note sans chiffre passe intacte', () => {
  assertEquals(sanitizeNotes('Photo nette et bien cadrée.'), 'Photo nette et bien cadrée.');
});

Deno.test('des notes absentes restent absentes', () => {
  assertEquals(sanitizeNotes(undefined), undefined);
  assertEquals(sanitizeNotes(''), undefined);
});

Deno.test('les notes sont tronquées à 160 caractères', () => {
  const cleaned = sanitizeNotes('x'.repeat(300));
  assertEquals(cleaned?.length, 160);
});
