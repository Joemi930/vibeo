# PROMPT PHASE 3 — Social & découverte de base (mode plan)

```
PHASE 3 : interactions sociales. Plan d'abord, attends ma validation.

Contenu :
1. Migrations : likes, comments, subscriptions, playlists, playlist_items,
   reports + RLS + triggers like_count + rate limiting (30 commentaires/h,
   20 signalements/j). [db-architect]
2. Likes + commentaires sur l'écran lecteur (liste paginée, ajout,
   suppression de SES commentaires, signalement d'un commentaire).
   [flutter-ui]
3. Page artiste publique : bannière, bio, badge vérifié, bouton S'abonner,
   grille de clips. [flutter-ui]
4. Bibliothèque : playlists (créer, renommer, supprimer, ajouter/retirer/
   réordonner des clips), liste des abonnements, historique de lecture.
   [flutter-ui]
5. Partage externe : lien web du clip (deep link go_router — le lien ouvre
   directement le lecteur sur web). [toi]
6. Recherche : titres + artistes (ILIKE + index trigram), filtres par genre,
   onglets Clips / Artistes. [db-architect pour l'index, flutter-ui pour l'UI]
7. Signalement de vidéos (bouton + motifs). [flutter-ui]
8. Tests : repositories sociaux, widgets (commentaires, playlists, page
   artiste) deux thèmes, intégration like+commentaire et création de
   playlist. [test-writer]
9. Audit RLS des nouvelles tables (surtout : qui peut supprimer quoi).
   [security-reviewer]

Critères de réussite :
- Deux comptes de test : A s'abonne à l'artiste B, like et commente un clip
  de B ; B ne peut pas supprimer le commentaire de A (mais A oui) ; les
  compteurs sont justes après actions répétées (pas de double like).
- Une playlist privée de A est invisible pour B (test RLS à me montrer).
- Le lien partagé ouvre le bon clip dans un navigateur non connecté.
- La recherche "tape 3 lettres" renvoie des résultats pertinents < 1 s.

Vérification graphique :
- Deux thèmes : saisie de commentaire (clavier ne cache pas le champ),
  swipe/réordonnancement des playlists, états vides (aucune playlist, aucun
  abonnement) avec call-to-action, bouton S'abonner : état changé
  immédiatement (optimistic UI). Liste-moi ce qui a été vérifié.
```
