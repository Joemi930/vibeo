// Abstraction du fournisseur d'IA (voir docs/ARCHITECTURE.md §2).
//
// Deux implémentations derrière une seule interface, choisies par la variable
// d'environnement `AI_PROVIDER` :
//
// - **Gemini** (défaut) — multimodal, palier gratuit. Seul capable d'analyser
//   une carte d'identité, ce qui en fait le seul choix viable pour
//   `verify-artist`.
// - **DeepSeek** — texte seul et payant (prépaiement : solde nul → HTTP 402).
//   Sous `AI_PROVIDER=deepseek`, l'analyse d'images est indisponible et la
//   vérification d'identité bascule intégralement en revue manuelle. C'est le
//   comportement prescrit par l'architecture, pas une dégradation accidentelle.
//
// Les clés vivent UNIQUEMENT dans les secrets Edge Functions (règle CLAUDE.md
// n°2). Aucune ne doit apparaître dans le code Flutter ni dans le dépôt.
//
// ─────────────────────────────────────────────────────────────────────────────
// RÈGLE D'OR : `analyzeText` et `analyzeImage` NE LÈVENT JAMAIS.
//
// Elles renvoient un résultat étiqueté. L'appelant doit pouvoir distinguer
// « l'IA a répondu non » — qui est une décision — de « l'IA n'a pas répondu » —
// qui n'en est pas une. Une exception confond les deux et conduit
// mécaniquement à rejeter des candidats pour cause de panne réseau. Sur des
// documents d'identité, c'est inacceptable.
// ─────────────────────────────────────────────────────────────────────────────
//
// Pas de rate limiting IA ici, et c'est délibéré : la consommation est déjà
// bornée en amont par les limites SQL du projet (1 candidature/semaine/personne,
// 5 publications/jour/artiste). En rajouter un serait un garde-fou redondant
// masquant la vraie barrière. Ne pas en ajouter « au cas où ».

/// Nature d'un échec. Ce qui compte pour l'appelant : `quota`, `network`,
/// `auth`, `invalid_output` et `unsupported` signifient tous « pas de
/// décision » ; `blocked` signifie « le fournisseur a refusé d'analyser », ce
/// qui pour une carte d'identité veut dire « document non exploitable », jamais
/// « document falsifié ».
export type AiFailureKind =
  | 'quota'
  | 'network'
  | 'auth'
  | 'invalid_output'
  | 'blocked'
  | 'unsupported';

export type AiResult =
  | { ok: true; data: unknown }
  | { ok: false; kind: AiFailureKind; detail: string };

export interface AiImage {
  bytes: Uint8Array;
  mimeType: string;
}

export interface AiProvider {
  readonly name: 'gemini' | 'deepseek' | 'none';
  readonly supportsImages: boolean;
  readonly model: string;
  analyzeText(prompt: string, jsonSchema: unknown): Promise<AiResult>;
  analyzeImage(
    prompt: string,
    image: AiImage,
    jsonSchema: unknown,
  ): Promise<AiResult>;
}

const REQUEST_TIMEOUT_MS = 20_000;

/// Un seul réessai, et seulement sur les échecs transitoires.
///
/// Le budget d'exécution d'une Edge Function ne permet pas une vraie politique
/// de reprise : mieux vaut rendre la main à la revue manuelle que faire
/// patienter l'utilisateur devant un formulaire qui tourne.
const RETRY_DELAY_MS = 1_500;

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/// Base64 sans passer par `String.fromCharCode(...bytes)`, qui déborde la pile
/// d'appels au-delà de ~100 Ko — soit toutes les photos de carte d'identité.
function toBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function failureFromStatus(status: number): AiFailureKind | null {
  // 402 = solde DeepSeek épuisé, 429 = trop de requêtes. Les deux veulent dire
  // « réessaie plus tard », donc pour nous : revue manuelle.
  if (status === 402 || status === 429) return 'quota';
  if (status === 401 || status === 403) return 'auth';
  if (status >= 500) return 'network';
  return null;
}

// ─────────────────────────────────────────────────────────── Gemini ──────────

class GeminiProvider implements AiProvider {
  readonly name = 'gemini' as const;
  readonly supportsImages = true;

  constructor(private readonly apiKey: string, readonly model: string) {}

  analyzeText(prompt: string, jsonSchema: unknown): Promise<AiResult> {
    return this.#generate([{ text: prompt }], jsonSchema);
  }

  analyzeImage(
    prompt: string,
    image: AiImage,
    jsonSchema: unknown,
  ): Promise<AiResult> {
    return this.#generate(
      [
        { text: prompt },
        {
          inline_data: {
            mime_type: image.mimeType,
            data: toBase64(image.bytes),
          },
        },
      ],
      jsonSchema,
    );
  }

  async #generate(parts: unknown[], jsonSchema: unknown): Promise<AiResult> {
    const first = await this.#attempt(parts, jsonSchema);
    if (first.ok || first.kind !== 'quota') return first;
    // Un seul réessai, et uniquement sur un quota momentané.
    await delay(RETRY_DELAY_MS + Math.floor(Math.random() * 500));
    return this.#attempt(parts, jsonSchema);
  }

  async #attempt(parts: unknown[], jsonSchema: unknown): Promise<AiResult> {
    let response: Response;
    try {
      response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            // La clé va dans un EN-TÊTE, jamais dans la chaîne de requête : une
            // URL est journalisée par tous les intermédiaires du chemin.
            'x-goog-api-key': this.apiKey,
          },
          body: JSON.stringify({
            contents: [{ role: 'user', parts }],
            generationConfig: {
              responseMimeType: 'application/json',
              responseSchema: jsonSchema,
              temperature: 0.1,
              maxOutputTokens: 512,
            },
          }),
          signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        },
      );
    } catch (error) {
      return { ok: false, kind: 'network', detail: String(error) };
    }

    if (!response.ok) {
      const kind = failureFromStatus(response.status) ?? 'invalid_output';
      return { ok: false, kind, detail: `HTTP ${response.status}` };
    }

    let body: Record<string, unknown>;
    try {
      body = await response.json();
    } catch (error) {
      return { ok: false, kind: 'invalid_output', detail: String(error) };
    }

    // Le filtre de sécurité de Gemini se déclenche parfois sur une photo de
    // pièce d'identité. C'est un refus d'analyser, PAS un indice de fraude :
    // l'appelant doit l'orienter vers la revue manuelle.
    const feedback = body.promptFeedback as { blockReason?: string } | undefined;
    if (feedback?.blockReason) {
      return { ok: false, kind: 'blocked', detail: feedback.blockReason };
    }

    const candidates = body.candidates as
      | Array<{
        finishReason?: string;
        content?: { parts?: Array<{ text?: string }> };
      }>
      | undefined;
    const candidate = candidates?.[0];
    if (!candidate) {
      return { ok: false, kind: 'invalid_output', detail: 'aucun candidat' };
    }
    if (candidate.finishReason === 'SAFETY') {
      return { ok: false, kind: 'blocked', detail: 'SAFETY' };
    }
    // JSON tronqué : le parser accepterait parfois un objet partiel. On refuse.
    if (candidate.finishReason === 'MAX_TOKENS') {
      return { ok: false, kind: 'invalid_output', detail: 'réponse tronquée' };
    }

    const text = candidate.content?.parts?.map((p) => p.text ?? '').join('');
    return parseJsonPayload(text);
  }
}

// ───────────────────────────────────────────────────────── DeepSeek ──────────

class DeepSeekProvider implements AiProvider {
  readonly name = 'deepseek' as const;
  // Texte seul : l'API officielle rejette les blocs image et aucun modèle
  // vision n'y est servi. Vérifié dans la doc, pas supposé.
  readonly supportsImages = false;

  constructor(private readonly apiKey: string, readonly model: string) {}

  async analyzeText(prompt: string, jsonSchema: unknown): Promise<AiResult> {
    const first = await this.#attempt(prompt, jsonSchema);
    if (first.ok || first.kind !== 'quota') return first;
    await delay(RETRY_DELAY_MS + Math.floor(Math.random() * 500));
    return this.#attempt(prompt, jsonSchema);
  }

  analyzeImage(): Promise<AiResult> {
    return Promise.resolve({
      ok: false,
      kind: 'unsupported',
      detail: 'DeepSeek n\'analyse pas les images.',
    });
  }

  async #attempt(prompt: string, jsonSchema: unknown): Promise<AiResult> {
    // DeepSeek n'accepte pas de schéma JSON strict : `json_object` garantit
    // seulement que la réponse est du JSON syntaxiquement valide. Le schéma est
    // donc glissé dans le prompt à titre indicatif, et la SEULE garantie de
    // forme reste la validation Zod faite par l'appelant.
    const instructions =
      `${prompt}\n\nRéponds en JSON strictement conforme à ce schéma, ` +
      `sans texte autour :\n${JSON.stringify(jsonSchema)}`;

    let response: Response;
    try {
      response = await fetch('https://api.deepseek.com/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: this.model,
          messages: [{ role: 'user', content: instructions }],
          response_format: { type: 'json_object' },
          temperature: 0.1,
          max_tokens: 512,
          stream: false,
        }),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      return { ok: false, kind: 'network', detail: String(error) };
    }

    if (!response.ok) {
      const kind = failureFromStatus(response.status) ?? 'invalid_output';
      return { ok: false, kind, detail: `HTTP ${response.status}` };
    }

    let body: Record<string, unknown>;
    try {
      body = await response.json();
    } catch (error) {
      return { ok: false, kind: 'invalid_output', detail: String(error) };
    }

    const choices = body.choices as
      | Array<{ finish_reason?: string; message?: { content?: string } }>
      | undefined;
    const choice = choices?.[0];
    if (!choice) {
      return { ok: false, kind: 'invalid_output', detail: 'aucun choix' };
    }
    if (choice.finish_reason === 'length') {
      return { ok: false, kind: 'invalid_output', detail: 'réponse tronquée' };
    }
    // La doc DeepSeek admet elle-même que l'API peut renvoyer un contenu vide.
    return parseJsonPayload(choice.message?.content);
  }
}

// ───────────────────────────────────────────────────────────── Aucun ─────────

/// Utilisé quand aucune clé n'est configurée.
///
/// Ne lève pas et ne bloque rien : tout renvoie `unsupported`, ce que
/// l'appelant traduit en revue manuelle. Une installation sans clé IA reste
/// donc pleinement fonctionnelle, simplement entièrement manuelle.
class NoneProvider implements AiProvider {
  readonly name = 'none' as const;
  readonly supportsImages = false;
  readonly model = 'none';

  analyzeText(): Promise<AiResult> {
    return Promise.resolve({
      ok: false,
      kind: 'unsupported',
      detail: 'Aucun fournisseur d\'IA configuré.',
    });
  }

  analyzeImage(): Promise<AiResult> {
    return this.analyzeText();
  }
}

// ─────────────────────────────────────────────────────────── Fabrique ────────

export function parseJsonPayload(text: string | undefined): AiResult {
  if (!text || text.trim().length === 0) {
    return { ok: false, kind: 'invalid_output', detail: 'réponse vide' };
  }
  try {
    return { ok: true, data: JSON.parse(text) };
  } catch (error) {
    return { ok: false, kind: 'invalid_output', detail: String(error) };
  }
}

/// Fournisseur configuré pour cette instance.
///
/// `AI_PROVIDER` vaut `gemini` (défaut) ou `deepseek`. Si la clé correspondante
/// manque, on renvoie [NoneProvider] plutôt que de lever : une clé absente est
/// un problème d'exploitation, pas une raison de refuser une candidature.
export function getAiProvider(): AiProvider {
  const choice = (Deno.env.get('AI_PROVIDER') ?? 'gemini').toLowerCase().trim();

  if (choice === 'deepseek') {
    // Le secret du projet est écrit `DEEPSEECK_API_KEY` (coquille d'origine).
    // On accepte les deux graphies pour ne pas dépendre d'un renommage manuel.
    const key = Deno.env.get('DEEPSEEK_API_KEY') ??
      Deno.env.get('DEEPSEECK_API_KEY');
    if (!key) return new NoneProvider();
    return new DeepSeekProvider(
      key,
      Deno.env.get('DEEPSEEK_MODEL') ?? 'deepseek-v4-flash',
    );
  }

  const key = Deno.env.get('GEMINI_API_KEY');
  if (!key) return new NoneProvider();
  // Le nom du modèle est configurable : la surface de l'API Gemini bouge vite
  // et un identifiant en dur devient faux sans prévenir (CLAUDE.md).
  return new GeminiProvider(
    key,
    Deno.env.get('GEMINI_MODEL') ?? 'gemini-2.5-flash',
  );
}
