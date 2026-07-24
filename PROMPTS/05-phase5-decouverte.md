# PROMPT PHASE 5 — Découverte : tendances & recommandations (mode plan)

```
PHASE 5 : rendre l'accueil vivant. Plan d'abord, attends ma validation.

Contenu :
1. Vue matérialisée trending_videos (score pondéré vues/likes/récence sur
   7 jours via view_events), rafraîchie par cron pg toutes les heures.
   [db-architect]
2. Fonction SQL de recommandations personnalisées : top genres écoutés par
   l'utilisateur × popularité récente, avec fallback tendances pour les
   nouveaux comptes (cold start). [db-architect]
3. Accueil final : sections Tendances, Nouveautés, Par genre (chips
   horizontales), Recommandé pour toi — avec scroll horizontal par section
   et pagination. [flutter-ui]
4. Écran "Tout voir" par section et par genre. [flutter-ui]
5. Historique de lecture alimenté proprement (déjà des view_events —
   l'écran Bibliothèque les affiche par date). [flutter-ui]
6. Performances : cache local des listes (éviter de recharger à chaque
   retour sur l'accueil), images de miniatures en cache. [toi]
7. Tests : logique de scoring (SQL testé via seed de données), providers de
   sections, widgets accueil deux thèmes, intégration navigation
   accueil→lecteur. [test-writer]

Critères de réussite :
- Avec un jeu de données seed (que tu crées : ~20 vidéos, 3 comptes, vues
  simulées), les tendances reflètent bien les vidéos les plus vues
  récemment et PAS les vieilles vidéos très vues il y a longtemps.
- Mon compte qui n'écoute que du rap voit du rap en premier dans
  "Recommandé pour toi" ; un compte neuf voit les tendances à la place.
- L'accueil se recharge instantanément en revenant d'un clip (cache).

Vérification graphique :
- Deux thèmes : scroll horizontal fluide, skeletons de chargement par
  section, section vide masquée proprement, chips de genre : état
  sélectionné visible, aucune image étirée/déformée dans les cards.
  Liste-moi ce qui a été vérifié.
```
