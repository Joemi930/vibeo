# AGENTS.md — Vibeo

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
- **video_player** (lecture ; `chewie` a été retiré, les contrôles sont maison) · **just_audio + audio_service** (audio
  arrière-plan)
- **ffmpeg_kit_flutter** : compression H.264 720p SUR L'APPAREIL avant upload
  (jamais de transcodage serveur — budget 0 €)
- **Sans IA** : la vérification des artistes est automatique (Phase 7).
- Web sur **Vercel**, CI sur **GitHub Actions**

## Commandes
```bash
flutter run -d chrome          # dev web
flutter run                    # dev Android
flutter analyze                # lint — doit passer sans erreur
flutter test                   # tests unitaires + widgets
flutter test integration_test  # parcours bout en bout (local : émulateur ou
                               # chromedriver requis, donc hors CI)
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
  functions/     # verify-artist/, moderate-video/,
                 # process-report/
test/            # miroir de lib/
integration_test/
docs/            # ARCHITECTURE.md et décisions
PROMPTS/         # prompts de phase fournis par l'utilisateur
```

## Règles de sécurité — NON NÉGOCIABLES
1. RLS activé sur **chaque** table dès sa création ; la migration qui crée une
   table inclut ses politiques dans le même fichier.
2. service_role : jamais dans le code Flutter ni le repo — secrets Edge
   Functions / variables d'env uniquement.
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
- `ffmpeg_kit_flutter` ne fonctionne pas sur le web : sur web, refuser les
  fichiers > 200 Mo et uploader tel quel (publication surtout depuis Android).
- `audio_service` nécessite une configuration AndroidManifest spécifique.
- Tier gratuit Supabase : 1 Go de storage — afficher l'usage dans l'admin.
- URLs signées Supabase sur web : configurer CORS du bucket.
