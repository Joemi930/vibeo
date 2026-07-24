# PROMPT PHASE 2 — Vidéo : upload, lecture, audio (mode plan)

```
PHASE 2 : le cœur vidéo de Vibeo. Plan d'abord, attends ma validation.

Contenu :
1. Migrations : table videos + RLS + triggers compteurs ; buckets privés
   videos et thumbnails avec politiques storage. [db-architect]
2. Upload (Studio artiste) : sélection fichier, compression on-device
   ffmpeg_kit (H.264 720p, plafond 200 Mo/8 min), extraction miniature,
   upload avec barre de progression via URL signée, formulaire titre/
   description/genre. Sur web : pas de compression, refus > 200 Mo.
   [flutter-ui + toi pour la logique ffmpeg]
3. Lecteur : plein écran, contrôles, description, écran de lecture complet ;
   mini-player persistant au-dessus de la bottom nav ; bascule mode audio
   arrière-plan (just_audio + audio_service, notification média, écran
   éteint OK sur Android). [flutter-ui + toi]
4. Accueil version 1 : liste des vidéos publiées (Nouveautés), VideoCard
   réutilisable. [flutter-ui]
5. Comptage des vues : view_events via fonction SQL sécurisée (vue comptée
   après 10 s de lecture), view_count par trigger. [db-architect]
6. Rate limiting : 5 uploads/jour/artiste côté serveur. [db-architect]
7. Tests : logique de compression (mockée), repository vidéos, widgets
   lecteur/mini-player deux thèmes, intégration upload→publication (statut
   processing) et lecture. [test-writer]
8. Audit upload + storage + URLs signées. [security-reviewer]

Note : à ce stade les vidéos passent en published directement après upload —
la modération IA arrive en phase 4 (prévoir le statut pending_moderation
dans le schéma dès maintenant).

Critères de réussite :
- Depuis Android : je filme/choisis une vidéo, elle se compresse (taille
  affichée avant/après), s'uploade avec progression, apparaît dans l'accueil.
- Lecture fluide Android + web ; le mini-player survit à la navigation ;
  l'audio continue écran éteint sur Android avec notification média.
- Impossible d'accéder à une vidéo sans URL signée (montre-moi le test :
  l'URL brute du bucket doit renvoyer 400/403).
- Le compteur de vues s'incrémente après 10 s, pas avant, et pas en spammant.

Vérification graphique :
- Parcours complet upload et lecture dans les deux thèmes : progression
  visible, états vide/erreur du lecteur, contrôles utilisables au doigt,
  mini-player : play/pause/fermer fonctionnels, aucun overflow en web étroit
  et large. Liste-moi ce qui a été vérifié.
```
