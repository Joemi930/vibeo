# CLAUDE.md — Vibeo

Plateforme de publication de clips vidéos pour artistes vérifiés (mélange
YouTube / YouTube Music). Cibles : **Android + Web**, une seule codebase
**Flutter**. Projet académique/portfolio, **budget infra : 0 €**, sécurité
**maximale**. Référence : `docs/ARCHITECTURE.md` — à lire avant toute décision.

## Ton rôle : ORCHESTRATEUR (session principale, Opus)
Tu es l'architecte et le chef d'équipe, pas le développeur de base :
1. Tu planifies chaque phase, découpes en tâches, et DÉLÈGUES aux agents
   spécialisés (tes développeurs) : `db-architect` (SQL/migrations/RLS),
   `flutter-ui` (écrans/widgets), `test-writer` (tests), `security-reviewer`
   (audit, lecture seule).
2. Tu vérifies leur travail : cohérence avec l'architecture, qualité, respect
   des règles de sécurité. Tu corriges toi-même les bugs majeurs ou
   transverses ; les corrections localisées repartent vers l'agent concerné.
3. Tu gardes le contexte global léger : l'exploration lourde et l'écriture de
   masse se font dans les agents, pas dans ta session.
4. Avant tout commit touchant auth, upload, Edge Functions, migrations ou
   admin : délègue un audit à `security-reviewer` et traite ses findings.
5. À la fin de chaque phase : résumé de ce qui est fait, comment le vérifier
   manuellement, et ce qui reste.

## Stack (ne pas dévier sans validation explicite)
- **Flutter 3.x / Dart** — Material 3, thème clair + sombre + système
- **Riverpod** (état) · **go_router** (navigation + deep links)
- **Supabase** : Postgres (RLS partout), Auth (email + Google), Storage,
  Edge Functions (Deno/TypeScript)
- **video_player + chewie** (lecture) · **just_audio + audio_service** (audio
  arrière-plan)
- **Compression 720p SUR L'APPAREIL** avant upload, jamais de transcodage
  serveur (budget 0 €). Plafond : **60 Mo / 4 min** par clip. Deux moteurs
  derrière une même interface (`lib/features/upload/data/video_compressor.dart`) :
  - Android : **video_compress** (encodeurs natifs). Remplace
    `ffmpeg_kit_flutter`, retiré par ses auteurs en 2025 — voir
    `docs/ARCHITECTURE.md` §2.
  - Web : **WebCodecs**, piloté par `mediabunny` (copie vendorée dans
    `web/js/`, MPL-2.0) via le module `web/js/vibeo_media.js`.
- **IA : Gemini API** (défaut, multimodal, tier gratuit) via le module
  `supabase/functions/_shared/ai-provider.ts` — abstraction permettant de
  basculer sur DeepSeek (`AI_PROVIDER=deepseek`, texte uniquement).
  Clés IA UNIQUEMENT dans les secrets Edge Functions.
- Web sur **Vercel**, CI sur **GitHub Actions**

## Commandes
```bash
flutter run -d chrome          # dev web
flutter run                    # dev Android
flutter analyze                # lint — doit passer sans erreur
flutter test                   # tests unitaires + widgets
flutter test integration_test  # tests d'intégration
dart format .                  # formatage
supabase start                 # stack locale (Docker requis)
supabase db diff -f <nom>      # générer une migration
supabase functions serve       # Edge Functions en local
```

## Structure du projet
```
lib/
  core/          # thème, router, constantes, utils, client Supabase, widgets partagés
  features/
    auth/        # chaque feature : data/ (repos), domain/ (modèles),
    home/        #                  presentation/ (écrans, widgets, providers)
    player/
    upload/
    artist/      # page artiste + candidature (carte d'identité)
    library/     # playlists, abonnements, historique
    search/
    admin/
    settings/
supabase/
  migrations/    # SQL versionné — TOUTE modif de schéma passe par ici
  functions/     # _shared/ai-provider.ts, verify-artist/, moderate-video/,
                 # process-report/
test/            # miroir de lib/
integration_test/
docs/            # ARCHITECTURE.md et décisions
PROMPTS/         # prompts de phase fournis par l'utilisateur
```

## Règles de sécurité — NON NÉGOCIABLES
1. RLS activé sur **chaque** table dès sa création ; la migration qui crée une
   table inclut ses politiques dans le même fichier.
2. service_role, clé Gemini/DeepSeek : jamais dans le code Flutter ni le repo —
   secrets Edge Functions / variables d'env uniquement.
3. Ne jamais committer `.env*` (le hook le bloque, ne pas contourner).
4. Buckets Storage privés ; accès uniquement par URL signée. Vérifier MIME +
   taille côté Edge Function.
5. Documents d'identité (bucket `identity-docs`) : lecture admins uniquement,
   URL signée 5 min, suppression automatique après décision (30 j max), aucune
   donnée du document stockée en base hors score/booléens.
6. Compteurs (view_count, like_count) modifiés par triggers SQL, jamais client.
7. Entrées Edge Functions validées avec Zod. Aucun SQL par concaténation.
8. Rate limiting : uploads 5/j/artiste, commentaires 30/h, candidatures
   1/semaine, signalements 20/j.
9. Aucun HTML rendu depuis du contenu utilisateur.
10. Audit `security-reviewer` obligatoire avant commit sensible.

## Conventions
- Code et identifiants en **anglais** ; UI, commentaires et commits en **français**.
- Commits : Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
- Chaque feature = branche `feat/<nom>` → PR → CI verte → merge. Jamais de
  push direct sur `main`.
- Tout modèle de données a un `fromJson`/`toJson` testé.
- Pas de `dynamic` sauf impossibilité prouvée ; null-safety stricte.
- Widgets : composition ; extraire dès qu'un `build` dépasse ~80 lignes.

## Définition de « terminé »
`flutter analyze` sans erreur ✚ tests écrits et verts (unitaires logique,
widget UI, intégration parcours critiques) ✚ RLS/validations en place si
données touchées ✚ fonctionne en Android ET web ✚ thèmes clair et sombre
corrects ✚ audit sécurité passé si zone sensible.

## Pièges connus
- Environnement : **Windows 11** — utiliser des commandes compatibles
  (les hooks tournent sous Git Bash).
- **Le registre de greffons web de Flutter se périme en silence.** Le fichier
  généré `.dart_tool/**/web_plugin_registrant.dart` peut rester figé à l'état
  d'une version antérieure du `pubspec` : les greffons ajoutés depuis
  ne sont alors **pas compilés dans le bundle**, sans le moindre avertissement.
  Symptôme : `UnimplementedError: <méthode>() has not been implemented`, ou une
  fonctionnalité qui « ne marche pas » sans erreur claire. C'est ainsi que la
  lecture vidéo et le partage ont été inertes pendant toute la Phase 3 alors que
  le code était juste. Vérifier :
  `grep -c "videoPlayer-" build/web/main.dart.js` (0 = greffon absent).
  Remède : `flutter clean` puis reconstruire. **Faire ce nettoyage après toute
  modification de dépendances**, sinon on debogue du code sain.
- Le navigateur d'aperçu automatisé ne compose aucune frame quand son panneau
  est masqué : `requestAnimationFrame` ne se déclenche pas, Flutter ne dessine
  rien, il n'y a **aucun canvas** et les vues plateforme ne s'attachent jamais.
  Le code Dart s'exécute pourtant (requêtes réseau, journaux). Ne jamais
  conclure « l'interface est cassée » à partir de ce navigateur ; vérifier le
  rendu dans un vrai navigateur.
- `video_compress` ne fonctionne pas sur le web (il dépend de `dart:io`) : il
  est isolé derrière un import conditionnel
  (`lib/features/upload/data/video_compressor.dart`). Le web compresse par
  WebCodecs à la place. **Firefox annonce l'API WebCodecs mais échoue à encoder
  du H.264** : tester par `canEncodeVideo`, jamais par la présence de l'API ;
  sans encodeur, le fichier part tel quel sous 60 Mo.
- Sur le web, le fichier choisi **reste côté JavaScript** ; Dart n'en reçoit
  qu'un identifiant. Charger les octets dans Dart faisait échouer la sélection
  des gros fichiers.
- Une contrainte `^3.0.4` fige la **majeure** : contrôler la version réellement
  résolue dans `pubspec.lock`, pas celle écrite dans `pubspec.yaml`. C'est ainsi
  qu'un `file_picker` de 2021 s'est retrouvé en production et cassait le web.
- Un H.264 en profil **4:4:4** (`yuv444p`, ce que choisit ffmpeg depuis une
  source RGB) n'est décodable par **aucun** navigateur, alors que
  `canPlayType('video/mp4')` répond « probably » — il ne teste que le
  conteneur. Toujours remonter le code `MediaError` réel.
- `audio_service` nécessite une configuration AndroidManifest spécifique.
- Tier gratuit Supabase : 1 Go de storage — afficher l'usage dans l'admin.
- URLs signées Supabase sur web : configurer CORS du bucket.
- Vérifier les noms de modèles Gemini/DeepSeek dans leur doc officielle au
  moment de l'implémentation (ils évoluent vite).
