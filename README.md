# Vibeo

Plateforme de publication de clips vidéos pour artistes vérifiés — mélange
YouTube / YouTube Music. **Android + Web**, une seule codebase Flutter.

[![CI](https://github.com/Joemi930/vibeo/actions/workflows/ci.yml/badge.svg)](https://github.com/Joemi930/vibeo/actions/workflows/ci.yml)
[![Pages](https://github.com/Joemi930/vibeo/actions/workflows/pages.yml/badge.svg)](https://joemi930.github.io/vibeo)

**Production :** https://joemi930.github.io/vibeo

## Stack

| Couche | Technologie |
|---|---|
| App | **Flutter 3.x (Dart)** — Material 3, thème clair/sombre |
| État | **Riverpod** — providers sans codegen |
| Navigation | **go_router** — deep links, hash URL strategy |
| Backend | **Supabase** — Postgres + Auth + Storage + Edge Functions |
| Hébergement | **GitHub Pages** — déploiement automatique via GitHub Actions |
| CI | **GitHub Actions** — analyze, tests, build, déploiement |

## Lancer en local

```bash
git clone https://github.com/Joemi930/vibeo.git
cd vibeo
flutter pub get

# Créer env.json :
echo '{"SUPABASE_URL":"https://ilqvqohjoekthxouwffd.supabase.co","SUPABASE_ANON_KEY":"sb_publishable_ot0IDcro7N4sKtOu713SBA_Y4OFg5b4"}' > env.json

# Web
flutter run -d chrome --dart-define-from-file=env.json

# Android
flutter run --dart-define-from-file=env.json
```

## Fonctionnalités

| Public | Artistes | Admins |
|---|---|---|
| Lecteur vidéo + mode audio | Upload avec compression on-device | Dashboard 6 onglets |
| Recherche clips & artistes | Studio de gestion des clips | Candidatures + vérification |
| Likes, commentaires | Page artiste + stats | Modération des contenus |
| Abonnements, playlists | Miniature automatique | Gestion des utilisateurs (création, rôles, bannissement) |
| Historique de lecture | Publication directe | Fiche détaillée par utilisateur |
| Signalements (7 motifs) | Badge vérifié | Journal de modération complet |
| Profil éditable | — | Statistiques + jauge de stockage |

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)** — Stack, base de données, sécurité, phases
- **[Présentation V1](docs/PRESENTATION.md)** — Fonctionnalités, guide de test, retours attendus
- **[Guide d'installation](docs/SETUP.md)** — Prérequis, configuration, déploiement

## Commandes

```bash
flutter analyze          # Lint
flutter test             # Tests unitaires + widgets (333+)
flutter build apk        # APK Android release
flutter build web        # Build web (GitHub Pages)
supabase functions deploy # Déployer une Edge Function
supabase db push         # Appliquer les migrations
```

## Conventions

- Code et identifiants en **anglais** ; UI, commentaires et commits en **français**
- Commits : [Conventional Commits](https://www.conventionalcommits.org)
- Branches : `feat/<nom>` → PR → CI verte → merge
- Tout modèle a un `fromJson`/`toJson` testé
- Pas de `dynamic` sauf impossibilité prouvée

---

> Projet portfolio — Joemi Tete · Budget : 0 € · Sécurité maximale
