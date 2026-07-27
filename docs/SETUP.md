# Guide d'installation et de développement — Vibeo

> Pour les collaborateurs qui souhaitent cloner le projet et le faire tourner en local.

## Prérequis

| Outil | Version | Installation |
|---|---|---|
| **Flutter** | 3.44.7 (stable) | https://docs.flutter.dev/get-started/install |
| **Git** | 2.x+ | https://git-scm.com |
| **Android Studio** | 2024+ | https://developer.android.com/studio (pour l'émulateur et le SDK Android) |
| **Supabase CLI** | 2.x | `npm i -g supabase` ou `scoop install supabase` |
| **Deno** | 2.x | https://deno.com (pour tester les Edge Functions) |
| **Node.js** | 18+ | https://nodejs.org (pour la CLI Vercel et Supabase) |

Vérifie ton installation :
```bash
flutter doctor
git --version
supabase --version
deno --version
```

## Cloner le projet

```bash
git clone https://github.com/Joemi930/vibeo.git
cd vibeo
flutter pub get
```

## Fichier `env.json`

Crée un fichier `env.json` à la racine du projet avec les clés de développement :

```json
{
  "SUPABASE_URL": "https://ilqvqohjoekthxouwffd.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_ot0IDcro7N4sKtOu713SBA_Y4OFg5b4"
}
```

> ⚠️ Ce fichier est dans `.gitignore` — il n'est jamais commité.

## Lancer l'application

### Web (développement)
```bash
flutter run -d chrome --dart-define-from-file=env.json
```

### Web (release local)
```bash
flutter run --release -d web-server --web-hostname 127.0.0.1 --web-port 8080 --dart-define-from-file=env.json
```

### Android
```bash
flutter run --dart-define-from-file=env.json
```

### APK release
```bash
flutter build apk --release --dart-define-from-file=env.json
# APK dans build/app/outputs/flutter-apk/app-release.apk
```

### Web release (pour Vercel)
```bash
flutter build web --release --csp --dart-define-from-file=env.json
# Sortie dans build/web/
```

## Base de données — Supabase

### Migrations

Les migrations SQL sont dans `supabase/migrations/`. Pour les appliquer au cloud :

```bash
supabase link --project-ref ilqvqohjoekthxouwffd
supabase db push
```

### Edge Functions

```bash
# Déployer une fonction
supabase functions deploy moderate-video
supabase functions deploy verify-artist
supabase functions deploy admin-actions
supabase functions deploy purge-identity-docs

# Tester en local
supabase functions serve
```

### Tester les Edge Functions
```bash
deno test --allow-net --allow-env supabase/functions/tests/
```

## Structure du projet

```
lib/
  core/           # Thème, router, constantes, widgets partagés
  features/
    admin/        # Dashboard d'administration
    artist/       # Candidature artiste
    auth/         # Connexion, inscription, Google
    home/         # Accueil — tendances, recommandations
    library/      # Playlists, abonnements, historique
    player/       # Lecteur vidéo + mode audio
    profile/      # Profil utilisateur
    search/       # Recherche clips + artistes
    settings/     # Paramètres, compte, confidentialité
    studio/       # Studio artiste, upload, gestion des clips
    upload/       # Parcours de publication (compression, détails)
    video/        # Domaine vidéo (modèle, repository, providers)
    social/       # Likes, commentaires, abonnements, playlists
supabase/
  migrations/     # Fichiers SQL versionnés
  functions/      # Edge Functions (Deno / TypeScript)
    _shared/      # Code partagé (require-admin, ai-provider, etc.)
    tests/        # Tests Deno
test/             # Tests Flutter (miroir de lib/)
docs/             # Documentation
Maquettes/        # Maquettes HTML de référence
```

## Conventions de code

| Règle | Détail |
|---|---|
| **Langue** | Code et identifiants en **anglais** ; UI, commentaires et commits en **français** |
| **Commits** | [Conventional Commits](https://www.conventionalcommits.org) : `feat:`, `fix:`, `test:`, `docs:`, `chore:` |
| **Branches** | `feat/<nom>` → PR → CI verte → merge dans `main` |
| **Analyse** | `flutter analyze` doit passer sans erreur avant chaque commit |
| **Tests** | `flutter test` doit être vert — 333+ tests actuellement |
| **Format** | `dart format .` avant de committer |
| **Sécurité** | Jamais de clé dans le code ; tout passe par `env.json` ou les secrets Edge Functions |

## CI/CD

Le projet utilise GitHub Actions (`.github/workflows/ci.yml`) :
- Scan de secrets (Gitleaks)
- `flutter analyze`
- `dart format --set-exit-if-changed`
- `flutter test`
- `flutter build web` (vérifie que le build web compile)
- `deno test` pour les Edge Functions

Le déploiement Vercel se fait via `vercel build --prod && vercel deploy --prebuilt --prod`.

## Comptes de test

| Rôle | Email | Usage |
|---|---|---|
| Admin | `Admin@admin.test` | Dashboard, modération, signalements |
| Admin | `joemitete12@gmail.com` | Admin principal |
