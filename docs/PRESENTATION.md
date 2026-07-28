# Vibeo — Dossier de présentation V1

> Plateforme de publication de clips vidéos pour artistes vérifiés.
> Projet portfolio — Joemi Tete · Juillet 2026

---

## 🎯 Qu'est-ce que Vibeo ?

Vibeo est une plateforme où les **artistes vérifiés** publient leurs clips
musicaux. Le public les découvre, les écoute en mode audio (écran éteint),
s'abonne aux artistes, crée des playlists, et signale les contenus
problématiques.

Un mélange **YouTube** (lecture vidéo) et **YouTube Music** (mode audio
arrière-plan), avec une vérification d'identité des artistes et un dashboard
d'administration.

**Stack :** Flutter (Android + Web) · Supabase (Postgres, Auth, Storage) ·
GitHub Pages · Gemini IA

---

## 🏗 Architecture

```
┌──────────────────────────┐        ┌──────────────────────────┐
│   Flutter (Dart)          │        │   Supabase                │
│   ├── Android (APK)       │◄──────►│   ├── Postgres + RLS      │
│   └── Web (GitHub Pages)   │  HTTPS │   ├── Auth (email+Google) │
│                            │        │   ├── Storage (privé)    │
│   Compression sur l'appareil        │   └── Edge Functions     │
│   (720p max, 60 Mo / 4 min)        └───────────┬──────────────┘
└──────────────────────────┘                     │
                                      ┌──────────▼──────────────┐
                                      │   Gemini API (IA)        │
                                      │   Modération + Vérif.    │
                                      │   artistes dans les      │
                                      │   Edge Functions         │
                                      └──────────────────────────┘
```

**Points clés :**
- **Budget infra : 0 €** — tout tient dans le tier gratuit Supabase + GitHub Pages
- **Compression sur l'appareil** : 720p AVANT upload, jamais de transcodage serveur
- **RLS (Row Level Security)** activé sur chaque table — le client ne peut pas tricher
- **IA** : Gemini (multimodal) pour la modération de contenu et la vérification d'identité

---

## 📱 Fonctionnalités V1 — Parcours utilisateur

### 🎵 Pour les auditeurs (rôle `listener`)

| Fonctionnalité | Description |
|---|---|
| **Accueil** | Tendances, Recommandé pour toi, Nouveautés — 3 carrousels + grille |
| **Lecteur vidéo** | Plein écran 16:9, contrôles maison, likes, commentaires, partage |
| **Mode audio** | Bascule en lecture audio seule avec notification — écran éteint OK |
| **Mini-player** | Lecture persistante pendant la navigation entre onglets |
| **Recherche** | Clips + artistes, filtres par genre |
| **Page artiste** | Bio, badge vérifié, grille des clips, bouton S'abonner |
| **Bibliothèque** | Playlists, abonnements, historique de lecture |
| **Profil** | Avatar, nom affiché, bio — édition complète |
| **Paramètres** | Thème clair/sombre/système, compte, confidentialité |
| **Signalements** | Signaler un clip ou commentaire — 7 motifs |

### 🎬 Pour les artistes (rôle `artist`)

| Fonctionnalité | Description |
|---|---|
| **Candidature** | Formulaire : nom de scène, liens, présentation |
| **Studio** | Upload de clip avec compression automatique + progression |
| **Miniature** | Extraite automatiquement ou choisie manuellement |
| **Gestion des clips** | Liste de ses clips, modification titre/description/genre |

### 🛡 Pour les administrateurs (rôle `admin`)

| Fonctionnalité | Description |
|---|---|
| **Dashboard** | Sidebar 6 onglets : Candidatures, Modération, Signalements, Utilisateurs, Stats, Journal |
| **Candidatures** | Examen et décision (approuver/rejeter), visionneuse sécurisée des pièces d'identité |
| **Modération vidéos** | File d'attente des clips, retrait manuel, republication |
| **Signalements** | Traitement priorisé : retirer le contenu, avertir l'auteur ou ignorer |
| **Utilisateurs** | Liste avec recherche et filtres par rôle, fiche détaillée par utilisateur (vidéos, commentaires, playlists, abonnements, signalements, journal), création de compte admin, changement de rôle, bannissement, suppression |
| **Statistiques** | Utilisateurs, artistes, clips, vues, stockage utilisé, jauge de quota |
| **Journal** | Historique complet et filtrable de toutes les actions de modération |

---

## 🔒 Sécurité — 10 règles non négociables

1. **RLS** activé sur chaque table dès sa création
2. `service_role` et clés IA **jamais** dans le code Flutter — uniquement secrets Edge Functions
3. **Jamais** de `.env` commité
4. Buckets Storage **privés** — accès par URL signée uniquement
5. Documents d'identité : lecture admin uniquement, URL 5 min, suppression automatique après décision
6. Compteurs (`view_count`, `like_count`) modifiés par **triggers SQL**, jamais par le client
7. Entrées Edge Functions validées avec **Zod** — jamais de SQL par concaténation
8. **Rate limiting** : 5 uploads/j/artiste, 30 commentaires/h, 1 candidature/semaine, 20 signalements/j
9. Aucun HTML rendu depuis du contenu utilisateur
10. CI : **Gitleaks** scan les secrets dans l'historique Git

---

## 🧪 Guide de test pour les amis du groupe

### Comptes de test

| Rôle | Email | Mot de passe |
|---|---|---|
| **Admin** | `Admin@admin.test` | *(défini lors de la création)* |
| **Admin** | `joemitete12@gmail.com` | Ton mot de passe Google |

> Pour créer un compte auditeur ou artiste : utilise l'écran d'inscription
> (email + mot de passe) ou « Se connecter avec Google ».

### Scénarios à tester

1. **Inscription** — Crée un compte avec email + mot de passe
2. **Connexion Google** — Connecte-toi avec Google
3. **Lecture vidéo** — Ouvre un clip, teste pause, avance, plein écran
4. **Mode audio** — Depuis le lecteur, bascule en mode audio → écran éteint
5. **Retour vidéo** — Depuis le mode audio, bouton « Revenir à la vidéo »
6. **Recherche** — Cherche un artiste ou un clip par mot-clé ou genre
7. **Bibliothèque** — Crée une playlist, ajoute des clips
8. **Profil** — Modifie ton avatar, ta bio
9. **Devenir artiste** — Remplis le formulaire de candidature
10. **Studio** — Upload un clip vidéo (Android uniquement)
11. **Paramètres** — Change le thème clair/sombre
12. **Dashboard admin** — Connecte-toi en admin, explore les 6 onglets
13. **Gestion utilisateurs** — Recherche un utilisateur, filtre par rôle, ouvre sa fiche détaillée, explore ses vidéos/commentaires/signalements
14. **Création de compte** — Depuis l'admin, crée un compte avec le rôle de ton choix
15. **Bannissement** — Bannis un compte, vérifie qu'il ne peut plus se connecter, puis débannis-le
16. **Signalement** — Signale un clip, puis traite-le depuis le dashboard admin
17. **Déconnexion** — Déconnecte-toi, reconnecte-toi avec un autre compte

### URLs

| Environnement | URL |
|---|---|
| **Production (GitHub Pages)** | https://joemi930.github.io/vibeo |
| **Local** | http://127.0.0.1:8080 |

---

## 📋 Retours attendus

Pour chaque test, note :

| Ce qui a marché | Ce qui a planté | Idée d'amélioration |
|---|---|---|
| ✅ ... | ❌ ... | 💡 ... |

**Questions spécifiques :**
- L'interface est-elle intuitive ?
- Le mode audio fonctionne-t-il écran éteint (Android) ?
- La compression vidéo est-elle assez rapide ?
- Le dashboard admin est-il clair ?
- As-tu réussi à publier un clip du début à la fin ?
- Y a-t-il des lenteurs ou des bugs ?

---

## 🎨 Identité visuelle

- **Couleur signature** : dégradé violet `#7C3AED` → `#4F46E5`
- **Logo** : 5 barres d'égaliseur formant un V
- **Thème** : Material 3 — clair, sombre, et système
- **Typographie** : Google Fonts (Space Mono pour les badges)

---

## 📊 Chiffres V1

| Métrique | Valeur |
|---|---|
| **Tests** | 333+ (Flutter) + 54 (Edge Functions) |
| **Fichiers Dart** | 210+ |
| **Migrations SQL** | 20 |
| **Edge Functions** | 4 (verify-artist, moderate-video, admin-actions, purge-identity-docs) |
| **Écrans** | 18+ |
| **Rôles** | 3 (listener, artist, admin) |
| **Compression** | 720p / 60 Mo / 4 min — 100% sur l'appareil |
| **Coût mensuel** | 0 € |

---

## 🔮 V2 — Pistes d'évolution

| Fonctionnalité | Description |
|---|---|
| **Recommandations IA** | Suggestions personnalisées basées sur l'historique d'écoute |
| **Tendances temps réel** | Classement dynamique des clips les plus regardés |
| **Notifications push** | Nouveaux clips des abonnements, réponses aux commentaires |
| **Playlists collaboratives** | Plusieurs utilisateurs éditent une même playlist |
| **Analytics artiste** | Dashboard de statistiques pour les artistes (vues, audience, rétention) |
| **Mode hors-ligne** | Téléchargement des clips pour lecture sans connexion |
| **Partage social** | Stories, intégration TikTok/Instagram |
| **Monétisation** | Pourboires, abonnements payants, split revenus |

---

> **Contact :** Joemi Tete · GitHub : [Joemi930/vibeo](https://github.com/Joemi930/vibeo)
