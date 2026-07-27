// Tests de la couche d'abstraction IA.
//
// Lancement :  deno test --allow-net --allow-env supabase/functions/tests/
//
// **Aucun appel réel n'est fait à Gemini ni à DeepSeek.** `globalThis.fetch`
// est remplacé le temps de chaque test. C'est une exigence, pas une commodité :
// un test qui contacterait le vrai service consommerait un quota, échouerait
// hors ligne, et ne prouverait rien de reproductible.
//
// Ce qui est vérifié ici est le contrat qui compte pour l'appelant : **ces
// méthodes ne lèvent jamais** et étiquettent correctement la nature de l'échec.
// Confondre « l'IA a répondu non » et « l'IA n'a pas répondu » ferait rejeter
// des candidats pour cause de panne réseau.

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import {
  type AiProvider,
  getAiProvider,
  parseJsonPayload,
} from '../_shared/ai-provider.ts';

const realFetch = globalThis.fetch;

/// Remplace `fetch` le temps d'un test, et le restaure quoi qu'il arrive.
async function withFetch(
  handler: (input: string | URL | Request, init?: RequestInit) => Response,
  body: () => Promise<void>,
): Promise<void> {
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) =>
    Promise.resolve(handler(input, init))) as typeof fetch;
  try {
    await body();
  } finally {
    globalThis.fetch = realFetch;
  }
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function geminiOk(text: string): Response {
  return json({ candidates: [{ content: { parts: [{ text }] } }] });
}

function withEnv(
  vars: Record<string, string | undefined>,
  body: () => void | Promise<void>,
): Promise<void> {
  const previous: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(vars)) {
    previous[key] = Deno.env.get(key);
    if (value === undefined) Deno.env.delete(key);
    else Deno.env.set(key, value);
  }
  const restore = () => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  };
  return Promise.resolve(body()).finally(restore);
}

function gemini(): Promise<AiProvider> {
  return Promise.resolve(getAiProvider());
}

// ── Sélection du fournisseur ────────────────────────────────────────────────

Deno.test('Gemini est le fournisseur par défaut', () =>
  withEnv(
    { AI_PROVIDER: undefined, GEMINI_API_KEY: 'clef-de-test' },
    () => {
      const provider = getAiProvider();
      assertEquals(provider.name, 'gemini');
      assertEquals(provider.supportsImages, true);
    },
  ));

Deno.test('DeepSeek n\'annonce pas savoir lire les images', () =>
  withEnv(
    { AI_PROVIDER: 'deepseek', DEEPSEEK_API_KEY: 'clef-de-test' },
    () => {
      const provider = getAiProvider();
      assertEquals(provider.name, 'deepseek');
      // C'est ce booléen qui fait basculer `verify-artist` en revue manuelle.
      assertEquals(provider.supportsImages, false);
    },
  ));

Deno.test('la graphie DEEPSEECK_API_KEY est acceptée', () =>
  withEnv(
    {
      AI_PROVIDER: 'deepseek',
      DEEPSEEK_API_KEY: undefined,
      DEEPSEECK_API_KEY: 'clef-de-test',
    },
    () => {
      // Le secret du projet porte cette coquille ; dépendre d'un renommage
      // manuel exposerait à une IA silencieusement désactivée.
      assertEquals(getAiProvider().name, 'deepseek');
    },
  ));

Deno.test('sans clé, le fournisseur « none » est renvoyé sans lever', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: undefined },
    async () => {
      const provider = getAiProvider();
      assertEquals(provider.name, 'none');
      const result = await provider.analyzeText('bonjour', {});
      assertEquals(result.ok, false);
      if (!result.ok) assertEquals(result.kind, 'unsupported');
    },
  ));

Deno.test('« none » refuse aussi les images, sans lever', () =>
  withEnv({ AI_PROVIDER: 'gemini', GEMINI_API_KEY: undefined }, async () => {
    const result = await getAiProvider().analyzeImage(
      'x',
      { bytes: new Uint8Array([1, 2, 3]), mimeType: 'image/png' },
      {},
    );
    assertEquals(result.ok, false);
  }));

Deno.test('DeepSeek refuse explicitement l\'analyse d\'image', () =>
  withEnv(
    { AI_PROVIDER: 'deepseek', DEEPSEEK_API_KEY: 'clef-de-test' },
    async () => {
      const result = await getAiProvider().analyzeImage(
        'x',
        { bytes: new Uint8Array([1]), mimeType: 'image/png' },
        {},
      );
      assertEquals(result.ok, false);
      if (!result.ok) assertEquals(result.kind, 'unsupported');
    },
  ));

Deno.test('le modèle est configurable par variable d\'environnement', () =>
  withEnv(
    {
      AI_PROVIDER: 'gemini',
      GEMINI_API_KEY: 'clef-de-test',
      GEMINI_MODEL: 'gemini-3.5-flash',
    },
    () => assertEquals(getAiProvider().model, 'gemini-3.5-flash'),
  ));

// ── Classification des échecs ───────────────────────────────────────────────

Deno.test('HTTP 429 est classé « quota » (et non une décision)', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(() => json({ error: 'rate limited' }, 429), async () => {
        const result = await (await gemini()).analyzeText('x', {});
        assertEquals(result.ok, false);
        if (!result.ok) assertEquals(result.kind, 'quota');
      }),
  ));

Deno.test('HTTP 402 (solde DeepSeek épuisé) est classé « quota »', () =>
  withEnv(
    { AI_PROVIDER: 'deepseek', DEEPSEEK_API_KEY: 'clef-de-test' },
    () =>
      withFetch(() => json({ error: 'Insufficient Balance' }, 402), async () => {
        const result = await getAiProvider().analyzeText('x', {});
        assertEquals(result.ok, false);
        if (!result.ok) assertEquals(result.kind, 'quota');
      }),
  ));

Deno.test('HTTP 401 est classé « auth »', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'mauvaise-clef' },
    () =>
      withFetch(() => json({ error: 'bad key' }, 401), async () => {
        const result = await (await gemini()).analyzeText('x', {});
        if (!result.ok) assertEquals(result.kind, 'auth');
      }),
  ));

Deno.test('HTTP 500 est classé « network »', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(() => json({}, 503), async () => {
        const result = await (await gemini()).analyzeText('x', {});
        if (!result.ok) assertEquals(result.kind, 'network');
      }),
  ));

Deno.test('un blocage du filtre de sécurité est classé « blocked »', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(
        () => json({ promptFeedback: { blockReason: 'SAFETY' } }),
        async () => {
          // Distinct de « quota » ou « invalid_output » : c'est ce qui permet à
          // la règle de décision de ne PAS confondre un refus d'analyser avec
          // un document falsifié.
          const result = await (await gemini()).analyzeText('x', {});
          assertEquals(result.ok, false);
          if (!result.ok) assertEquals(result.kind, 'blocked');
        },
      ),
  ));

Deno.test('une réponse tronquée est classée « invalid_output »', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(
        () =>
          json({
            candidates: [{
              finishReason: 'MAX_TOKENS',
              content: { parts: [{ text: '{"readable":tr' }] },
            }],
          }),
        async () => {
          const result = await (await gemini()).analyzeText('x', {});
          assertEquals(result.ok, false);
          if (!result.ok) assertEquals(result.kind, 'invalid_output');
        },
      ),
  ));

Deno.test('un JSON invalide est classé « invalid_output », sans lever', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(() => geminiOk('ceci n\'est pas du JSON'), async () => {
        const result = await (await gemini()).analyzeText('x', {});
        assertEquals(result.ok, false);
        if (!result.ok) assertEquals(result.kind, 'invalid_output');
      }),
  ));

Deno.test('une réponse vide est classée « invalid_output »', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(() => json({ candidates: [] }), async () => {
        const result = await (await gemini()).analyzeText('x', {});
        assertEquals(result.ok, false);
      }),
  ));

Deno.test('une panne réseau ne lève pas, elle est classée « network »', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    async () => {
      globalThis.fetch = (() =>
        Promise.reject(new TypeError('connexion refusée'))) as typeof fetch;
      try {
        const result = await getAiProvider().analyzeText('x', {});
        assertEquals(result.ok, false);
        if (!result.ok) assertEquals(result.kind, 'network');
      } finally {
        globalThis.fetch = realFetch;
      }
    },
  ));

// ── Chemin nominal ──────────────────────────────────────────────────────────

Deno.test('une réponse valide est renvoyée telle quelle', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-de-test' },
    () =>
      withFetch(() => geminiOk('{"coherent":true,"confidence":72}'), async () => {
        const result = await (await gemini()).analyzeText('x', {});
        assertEquals(result.ok, true);
        if (result.ok) {
          assertEquals(
            (result.data as { confidence: number }).confidence,
            72,
          );
        }
      }),
  ));

Deno.test('la clé Gemini voyage en en-tête, jamais dans l\'URL', () =>
  withEnv(
    { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'clef-tres-secrete' },
    () => {
      let seenUrl = '';
      let seenHeader: string | undefined;
      return withFetch(
        (input, init) => {
          seenUrl = String(input);
          seenHeader =
            (init?.headers as Record<string, string>)['x-goog-api-key'];
          return geminiOk('{}');
        },
        async () => {
          await (await gemini()).analyzeText('x', {});
          // Une URL est journalisée par tous les intermédiaires du chemin.
          assertEquals(seenUrl.includes('clef-tres-secrete'), false);
          assertEquals(seenHeader, 'clef-tres-secrete');
        },
      );
    },
  ));

Deno.test('DeepSeek s\'authentifie en Bearer, pas dans l\'URL', () =>
  withEnv(
    { AI_PROVIDER: 'deepseek', DEEPSEEK_API_KEY: 'clef-tres-secrete' },
    () => {
      let seenUrl = '';
      let seenAuth: string | undefined;
      return withFetch(
        (input, init) => {
          seenUrl = String(input);
          seenAuth = (init?.headers as Record<string, string>)['Authorization'];
          return json({ choices: [{ message: { content: '{}' } }] });
        },
        async () => {
          await getAiProvider().analyzeText('x', {});
          assertEquals(seenUrl.includes('clef-tres-secrete'), false);
          assertEquals(seenAuth, 'Bearer clef-tres-secrete');
        },
      );
    },
  ));

// ── Fonction utilitaire exposée ─────────────────────────────────────────────

Deno.test('parseJsonPayload refuse une chaîne vide', () => {
  const result = parseJsonPayload('');
  assertEquals(result.ok, false);
});

Deno.test('parseJsonPayload refuse undefined', () => {
  assertEquals(parseJsonPayload(undefined).ok, false);
});

Deno.test('parseJsonPayload accepte un objet bien formé', () => {
  const result = parseJsonPayload('{"a":1}');
  assertEquals(result.ok, true);
});
