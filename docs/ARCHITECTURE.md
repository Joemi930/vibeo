# Vibeo — Architecture complète

> Plateforme de publication de clips vidéos pour artistes vérifiés (Android + Web).
> Contexte : projet académique / portfolio · Budget : 0 € · Délai : 1-3 mois.

---

## 1. Vue d'ensemble

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│   Flutter (Dart)            │        │   Supabase (free tier)       │
│   ├── App Android (APK)     │◄──────►│   ├── Postgres + RLS         │
│   └── App Web (Vercel)      │  HTTPS │   ├── Auth (email + Google)  │
│                             │        │   ├── Storage (vidéos, imgs, │
│   Compression vidéo         │        │   │    docs d'identité)      │
│   on-device (ffmpeg_kit)    │        │   ├── Edge Functions (Deno)  │
└─────────────────────────────┘        │   └── Realtime (compteurs)   │
                                       └───────────┬──────────────────┘
                                                   │
                                       ┌───────────▼──────────────────┐
                                       │  IA (abstraction provider)   │
                                       │  Gemini (défaut, multimodal) │
                                       │  ou DeepSeek (texte)         │
                                       │  ├── Vérif. artistes + CNI   │
                                       │  └── Modération contenu      │
                                       └──────────────────────────────┘
```

## 2. Stack technique

| Couche | Choix | Pourquoi |
|---|---|---|
| App mobile + web | **Flutter 3.x (Dart)** | Une codebase, Material 3, thème clair/sombre |
| État | **Riverpod** | Standard moderne, testable |
| Navigation | **go_router** | Deep links (partage de clips), web-friendly |
| Backend | **Supabase** | Postgres + Auth + Storage + Edge Functions, gratuit |
| Hébergement web | **Vercel** (build Flutter web) | Gratuit, CDN, headers sécurité |
| Lecture vidéo | **video_player** + **chewie** | Streaming progressif MP4 |
| Audio arrière-plan | **just_audio** + **audio_service** | Notification média, mode "YT Music" |
| Compression vidéo | **ffmpeg_kit_flutter** (Android) | H.264 720p AVANT upload → budget 0 € |
| IA | **Gemini API** (tier gratuit, multimodal) via Edge Functions | Vérif. artistes + carte d'identité + modération. Abstraction provider → bascule DeepSeek possible (texte uniquement) |
| CI | **GitHub Actions** | analyze + tests + build à chaque push |

### Abstraction IA (Edge Functions)
Un module `_shared/ai-provider.ts` expose `analyzeText()` et `analyzeImage()`.
Implémentation par défaut : **Gemini** (tier gratuit + multimodal, indispensable
pour analyser cartes d'identité et miniatures). Implémentation alternative :
DeepSeek (texte seulement — si choisi, l'analyse d'images est désactivée et la
vérification d'identité passe systématiquement en revue manuelle admin).
Le choix se fait par la variable d'env `AI_PROVIDER` (gemini | deepseek).
Les clés API vivent UNIQUEMENT dans les secrets Edge Functions.

### Stratégie vidéo à 0 €
1. Compression SUR L'APPAREIL (H.264, 720p max, ~2 Mbps, plafond 200 Mo / 8 min).
2. Upload direct vers Supabase Storage (bucket privé `videos`) via URL signée.
3. Miniature extraite sur l'appareil (frame à 10 %).
4. Lecture en streaming progressif (range requests MP4) via URL signée 1 h.
5. Limite tier gratuit (1 Go stockage / 2 Go bande passante par mois) affichée
   dans le dashboard admin ; migration Cloudflare R2 documentée si croissance.

## 3. Base de données (Postgres — schéma cible)

```
profiles              (id PK → auth.users, username UNIQUE, display_name,
                       avatar_url, bio, role ENUM[listener|artist|admin],
                       created_at)

artist_applications   (id PK, user_id FK, stage_name, links JSONB,
                       statement TEXT, id_document_path TEXT,
                       ai_score NUMERIC, ai_analysis JSONB,
                       status ENUM[pending|approved|rejected|manual_review],
                       reviewed_by FK NULL, created_at, decided_at)

genres                (id PK, name, slug UNIQUE)

videos                (id PK, artist_id FK, title, description, genre_id FK,
                       video_path, thumbnail_path, duration_seconds, size_bytes,
                       status ENUM[processing|pending_moderation|published|
                                   rejected|removed],
                       moderation_result JSONB, view_count BIGINT DEFAULT 0,
                       like_count BIGINT DEFAULT 0, published_at, created_at)

likes                 (user_id FK, video_id FK, created_at, PK(user_id, video_id))
comments              (id PK, video_id FK, user_id FK, content, created_at,
                       deleted_at NULL)
subscriptions         (subscriber_id FK, artist_id FK, created_at,
                       PK(subscriber_id, artist_id))
playlists             (id PK, owner_id FK, title, is_public BOOL, created_at)
playlist_items        (playlist_id FK, video_id FK, position, PK(playlist, video))
reports               (id PK, target_type ENUM[video|comment], target_id,
                       reporter_id FK, reason ENUM[...], details,
                       status ENUM[open|reviewed|actioned|dismissed], created_at)
view_events           (id PK, video_id FK, user_id FK NULL, watched_seconds,
                       created_at)   -- alimente tendances + recommandations
moderation_logs       (id PK, actor ENUM[ai|admin], target_type, target_id,
                       action, reason, created_at)
```

**Règles clés :**
- RLS activé sur TOUTES les tables, aucune exception.
- Compteurs (view_count, like_count) mis à jour par triggers SQL, jamais par le client.
- Tendances = vue matérialisée sur view_events (fenêtre 7 jours), cron pg.
- Recommandations = scoring SQL simple : genres écoutés × popularité récente.

## 4. Vérification d'artiste avec carte d'identité

Parcours : formulaire (nom de scène, liens, présentation) + **upload obligatoire
de la carte d'identité** (photo/scan) → Edge Function `verify-artist` :

1. Le document part dans le bucket privé `identity-docs` (voir règles §5.4).
2. L'IA (Gemini, multimodal) analyse : lisibilité du document, cohérence
   nom/prénom vs profil, signes évidents de falsification, cohérence des liens
   fournis (réseaux, plateformes) → `ai_score` 0-100 + rapport `ai_analysis`.
3. Décision : score ≥ 80 ET document jugé lisible/cohérent → **approved** auto ·
   score ≤ 30 ou document illisible/incohérent → **rejected** auto avec motif ·
   entre les deux → **manual_review** (file d'attente admin avec le rapport IA).
4. L'admin qui traite un `manual_review` voit le document via URL signée
   très courte (5 min) et confirme/rejette.

**Protection des documents d'identité (donnée ultra-sensible) :**
- Bucket `identity-docs` : accès en lecture UNIQUEMENT aux admins (RLS storage),
  jamais listable publiquement, aucune URL longue durée.
- Le document est **supprimé automatiquement** (cron pg + storage) dès que la
  candidature est décidée, avec un délai maximum de 30 jours (minimisation des
  données). Seul le verdict et le rapport IA (sans données brutes du document)
  sont conservés.
- Aucun contenu du document (numéro, adresse…) n'est stocké en base — seul
  un booléen de cohérence et le score.

## 5. Fonctions IA (Edge Functions)

| Fonction | Déclencheur | Logique |
|---|---|---|
| `verify-artist` | Nouvelle candidature | Analyse dossier + carte d'identité (voir §4) |
| `moderate-video` | Vidéo uploadée (`pending_moderation`) | Analyse titre + description + miniature → publication auto ou file admin |
| `process-report` | Signalement créé | Priorisation automatique (gravité) |

## 6. Sécurité (niveau maximal)

1. **Auth** : Supabase Auth (JWT), email + Google Sign-In, vérification email.
2. **RLS** : politiques par table (un artiste ne modifie que SES vidéos ;
   seuls les admins lisent reports et identity-docs).
3. **Storage** : buckets privés, upload via URL signée avec vérif MIME + taille,
   lecture via URL signée expirante (1 h vidéos, 5 min documents d'identité).
4. **Edge Functions** : validation Zod sur chaque endpoint, jamais de SQL
   par concaténation, vérification du rôle côté serveur.
5. **Rate limiting** : 5 uploads/jour/artiste, 30 commentaires/h,
   1 candidature/semaine, 20 signalements/jour.
6. **Secrets** : .env jamais commité (hook + .gitignore), service_role et clés
   IA jamais dans l'app.
7. **Web (Vercel)** : headers CSP, X-Frame-Options, HSTS via vercel.json.
8. **Client** : contenu utilisateur affiché en texte brut, jamais de HTML injecté.
9. **CI** : analyze + tests bloquants, scan de secrets (gitleaks).
10. **Revue** : agent security-reviewer sur chaque fonctionnalité sensible.

## 7. Maquette — écrans (Material 3, sobre, clair/sombre)

1. **Onboarding / Auth** — connexion, inscription, Google, mot de passe oublié.
2. **Accueil** — Tendances, Nouveautés, Par genre, Recommandé pour toi.
3. **Recherche** — barre + filtres genre, résultats mixtes clips/artistes.
4. **Lecteur** — plein écran, likes/commentaires/partage, file d'attente ;
   mini-player persistant ; bascule mode audio (écran éteint OK).
5. **Page artiste** — bannière, bio, badge vérifié, S'abonner, grille de clips.
6. **Bibliothèque** — playlists, abonnements, historique.
7. **Studio artiste** — upload (progression + compression), mes clips, stats.
8. **Devenir artiste** — formulaire + upload carte d'identité + suivi du statut.
9. **Admin (web prioritaire)** — candidatures manual_review (avec visionneuse
   sécurisée du document), vidéos en modération, signalements, stats, journal.
10. **Paramètres** — thème clair/sombre/système, compte, déconnexion.

## 8. Phases de développement

| Phase | Contenu |
|---|---|
| **Config outils** | Faite PAR L'UTILISATEUR via GUIDE-CONFIGURATION.md |
| **P1 — Fondations + Auth** | Projet Flutter, thème, router, Supabase, CI, inscription/connexion/Google, profils, rôles |
| **P2 — Vidéo** | Upload + compression, storage, lecteur, mini-player, audio background |
| **P3 — Social** | Likes, commentaires, abonnements, playlists, partage, recherche, genres |
| **P4 — IA & vérification** | Candidature artiste + carte d'identité, modération vidéos, signalements |
| **P5 — Découverte** | Tendances, recommandations |
| **P6 — Admin & durcissement** | Dashboard admin, revue sécurité complète, tests d'intégration, polish |
