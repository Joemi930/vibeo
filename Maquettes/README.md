# Handoff: Vibeo — App vidéo musicale (mobile + web)

## Overview
Vibeo est une plateforme de clips musicaux vérifiés (artistes, auditeurs, modération). Ce lot couvre : identité de marque, design system Material 3 (2 thèmes), écrans mobile (accueil, lecteur, mode audio, profil artiste, candidature artiste, recherche, bibliothèque, studio artiste, upload, paramètres, skeletons) et écrans web desktop (accueil, lecteur, dashboard admin).

## About the Design Files
Les fichiers `.dc.html` de ce lot sont des **références de design créées en HTML** — des prototypes montrant le look et le comportement voulus, pas du code à copier tel quel. La tâche consiste à **recréer ces designs dans l'environnement du codebase cible** (React, Vue, SwiftUI, natif, etc.) en utilisant ses patterns et librairies existants — ou, s'il n'y a pas encore d'environnement, à choisir le framework le plus adapté au projet.

Chaque écran est un fichier autonome. Les fichiers "galerie" (`Vibeo Écrans - Étape 3/4/5…`, `Vibeo Design System`, `Vibeo Identité`) sont des planches de présentation qui importent les écrans individuels — ce sont les écrans individuels qu'il faut recréer, un par un.

## Fidelity
**Haute fidélité (hifi)** — couleurs, typographie, espacements et composants sont définitifs. Le développeur doit recréer l'UI au pixel près avec les librairies du codebase cible.

## Design Tokens

### Couleurs — Mode sombre (défaut)
- Fond : `#121016` · Surface +1 : `#1B1820` · Surface +2 : `#241F2B` · Surface +3 : `#2E2836`
- Primary : `#7C3AED` · Primary variant : `#8B5CF6` · Container : `#35216B` · On-container : `#E9DDFF`
- Accent : `#B69DF8`
- Texte primaire : `#F4F1F8` · secondaire : `#B9B2C7` · tertiaire : `#7C7589`
- Bordures : `#322C3D`
- Sémantiques : succès `#4ADE80` (bg `#12301F`) · attention `#FBBF24` (bg `#33270A`) · erreur `#FF6B6B` (bg `#3A1D22`) · info `#60A5FA`
- Dégradé signature : `linear-gradient(135deg, #7C3AED, #4F46E5)` — réservé aux CTA et moments forts

### Couleurs — Mode clair
- Fond : `#FAF9FC` · Surface +1 : `#FFFFFF` · Surface +2 : `#F2EFF9` · Surface +3 : `#E9E4F3`
- Primary : `#6C3BD9` · Container : `#EADDFF` · On-container : `#22005D`
- Texte primaire : `#1A1622` · secondaire : `#4A4458` · tertiaire : `#7C7589`
- Bordures : `#E1DBEC`
- Sémantiques : succès `#15803D` (bg `#DCFCE7`) · attention `#B45309` (bg `#FEF3C7`) · erreur `#DC2626` (bg `#FEE2E2`) · info `#2563EB`
- Même dégradé signature que le mode sombre (identique dans les deux thèmes)

### Typographie
Une seule famille : **Plus Jakarta Sans** (Google Fonts, graisses 400/500/600/700/800). Choisie pour son ouverture de contreformes (lisible en petite taille : compteurs de vues, labels de nav) et ses chiffres nets. Icônes : **Material Symbols Rounded**. Échelle :
- Display L : 45/52 · 700 — Headline L : 32/40 · 700 — Headline S : 24/32 · 600
- Title L : 20/28 · 600 — Body L : 16/24 · 400 — Label L : 14/20 · 600 (uppercase, +0.02em)

### Forme & espacement
- Rayons : 12px (cartes/champs) · 16-20px (feuilles/panneaux) · pilule/999px (boutons, chips, badges)
- Grille de base 4px
- Boutons : padding 11-15px vertical, 18-26px horizontal, radius pilule, 4 états (normal/hover/pressed/disabled) + variantes tonal/tertiaire/destructif

## Screens / Views

### Identité (Vibeo Identité.dc.html)
Logo retenu : **« Onde »** — un V formé par 5 barres d'égaliseur audio (hauteurs variables, la barre centrale plus courte en accent). Dégradé `#7C3AED → #4F46E5` sur les barres extérieures, `#B69DF8` sur la barre centrale. Déclinaisons : symbole seul, icône app carrée (radius 16px) et ronde, mono blanc/noir, testé à 24px.

### Mobile (390×844, iOS-style, safe areas 44px haut / ~34px bas)
- **Home** — top bar (logo + avatar), carrousel "Tendances" (grande carte 288px + petite 180px), chips de genres scrollables, rangées "Nouveautés"/"Recommandé" (cartes 158px, ratio 16:9), mini-player ancré + barre de progression, nav basse 4 items (Accueil/Recherche/Bibliothèque/Profil).
- **Player** — vidéo 16:9 en haut avec contrôles overlay, titre, ligne artiste + bouton S'abonner, rangée d'actions (Like/Commenter/Partager/Audio/Signaler), description repliable, fil de commentaires, champ de commentaire ancré en bas.
- **PlayerLandscape** — plein écran 844×390, contrôles overlay (retour 10s / lecture / avance 10s), actions latérales droite, timeline en bas.
- **AudioMode** — pochette carrée, titre + artiste, progress bar, transport (préc/-10s/lecture/+10s/suiv), bouton "Revenir à la vidéo", file d'attente.
- **Artist** — bannière + avatar rond superposé, stats (abonnés/clips), bio, CTA S'abonner + cloche, onglets (Clips/Playlists/À propos), grille 2 colonnes de clips.
- **BecomeArtist** — formulaire (nom de scène, liens, présentation), upload pièce d'identité (aperçu flouté), bandeau sécurité `lock`, case de consentement, CTA envoi.
- **ApplicationStatus** — hero statut "En cours d'analyse", timeline verticale 3 étapes (envoyée/en cours/décision) avec pastilles colorées, bandeau info suppression auto du document, CTA annuler.
- **Auth** — logo, toggle Connexion/Inscription, champs email/mot de passe, CTA primaire, séparateur "ou", bouton Google, mentions légales.
- **Search** / **SearchEmpty** — barre de recherche, chips de genre, onglets Clips/Artistes, résultats en liste (miniature 150px + méta) ; état vide avec icône `search_off` et CTA "Effacer la recherche".
- **Library** / **LibraryEmpty** — onglets Playlists/Abonnements/Historique, liste playlists (miniature 56px) ; état vide avec icône `playlist_add` et CTA "Crée ta première playlist".
- **Studio** — stats artiste (vues/likes/abonnés), CTA "Publier un clip", liste des clips avec statuts (Publié/En modération/Rejeté + motif du rejet en clair).
- **Upload1→4** — 1) dropzone + récents, 2) anneau de progression (compression, taille avant/après), 3) formulaire détails (miniature, titre, description, genre), 4) confirmation avec statut "En modération".
- **Settings** — sélecteur de thème (Sombre/Clair/Système) en 3 vignettes, section Compte (liens), déconnexion, zone de danger (suppression de compte) en rouge.
- **SkeletonHome** / **SkeletonLibrary** — états de chargement avec effet "shimmer" (`@keyframes shine`, gradient qui glisse, 1.5s ease-in-out infinite) sur des blocs gris reproduisant la mise en page finale.

### Web (1440×900)
- **WebHome** — sidebar fixe 248px (nav + abonnements + CTA "Devenir artiste"), top bar (recherche + notif + avatar), grille 4 colonnes de cartes vidéo, mini-player pleine largeur ancré en bas (transport centré, volume/queue/cast à droite).
- **WebPlayer** — vidéo large (~2/3 de largeur) à gauche avec titre/artiste/actions/description, colonne droite fixe 400px avec file "À suivre" + commentaires.
- **AdminDashboard** — sidebar 230px (Candidatures/Modération/Signalements/Stats/Journal + jauge de stockage), 3 cartes stats en haut, table des candidatures (colonnes Artiste/Date/Score IA/Statut/Actions, score en barre colorée), panneau latéral d'examen 384px (rapport IA avec checks, bandeau "Accès sécurisé — lien expirant" avec compte à rebours, visionneuse de document flouté, actions Approuver/Rejeter).

## Interactions & Behavior
- Thème sombre/clair : toggle global, persiste normalement en localStorage / préférence système.
- Bouton like : bascule rempli/contour (icône Material `favorite`, `font-variation-settings: 'FILL' 1` quand actif).
- Nav basse / sidebar : item actif en accent + icône remplie.
- Mini-player : persiste entre les écrans, cliquable pour rouvrir le lecteur plein écran ; bouton fermer le retire.
- Upload : 4 étapes séquentielles avec barre de progression segmentée en haut ; la compression affiche une estimation de taille en temps réel.
- États vides : toujours une icône + un message + un CTA, jamais un écran vide sans action.
- Skeletons : affichés pendant le chargement initial (~1-2s), remplacés par le contenu réel.
- Dashboard admin : sélection d'une ligne de candidature ouvre/actualise le panneau d'examen à droite ; le lien du document expire (compte à rebours visible), à réémettre après expiration.

## State Management
- Thème (sombre/clair/système) — global.
- Session utilisateur (connecté / invité) — conditionne l'accès à Studio, Devenir artiste, Bibliothèque.
- Statut de lecture (vidéo/audio, lecture/pause, position) — persiste en mini-player entre navigations.
- Statut de candidature artiste (brouillon → envoyée → en examen → approuvée/rejetée).
- Statut de modération par clip (en modération / publié / rejeté + motif).
- Recherche : requête + filtres genre + onglet (clips/artistes) + état vide.
- Upload : étape courante (1-4), fichier sélectionné, % de compression, métadonnées saisies.

## Assets
Aucune image/photo fournie — toutes les miniatures vidéo et avatars sont des placeholders (rayures diagonales ou dégradés violets). Le développeur doit prévoir de vrais visuels (miniatures 16:9, avatars, bannières artiste) à intégrer à la place. Le logo « Onde » est en SVG inline (5 rectangles arrondis + dégradé), reproductible directement en SVG ou en composant icône.

## Files
Écrans individuels (à recréer un par un) : `Home.dc.html`, `Player.dc.html`, `PlayerLandscape.dc.html`, `AudioMode.dc.html`, `Artist.dc.html`, `BecomeArtist.dc.html`, `ApplicationStatus.dc.html`, `Auth.dc.html`, `Search.dc.html`, `SearchEmpty.dc.html`, `Library.dc.html`, `LibraryEmpty.dc.html`, `Studio.dc.html`, `Upload1-4.dc.html`, `Settings.dc.html`, `SkeletonHome.dc.html`, `SkeletonLibrary.dc.html`, `WebHome.dc.html`, `WebPlayer.dc.html`, `AdminDashboard.dc.html`.

Planches de référence (assemblent les écrans ci-dessus, servent de contexte visuel) : `Vibeo Identité.dc.html`, `Vibeo Design System.dc.html`, `Vibeo Écrans - Étape 3.dc.html`, `Vibeo Écrans - Étape 4.dc.html`, `Vibeo Écrans - Étape 5 Web.dc.html`.

Chaque écran individuel utilise des variables CSS (`--bg`, `--tx`, `--pri`, `--acc`, `--out`, etc.) pour le thème — voir les valeurs listées dans "Design Tokens" ci-dessus pour les deux modes.
