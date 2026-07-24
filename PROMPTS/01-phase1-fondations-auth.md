# PROMPT PHASE 1 — Fondations + Auth & profils (mode plan)

```
PHASE 1 : Fondations + Authentification & profils. Plan d'abord, attends ma
validation.

Contenu :
1. Initialiser le projet Flutter (plateformes android + web uniquement) avec
   la structure de CLAUDE.md ; .gitignore complet ; .env.example documenté
   (SUPABASE_URL, SUPABASE_ANON_KEY via --dart-define).
2. Thème Material 3 clair + sombre + système, switch fonctionnel dans un
   écran Paramètres minimal. [flutter-ui]
3. go_router : routes squelettes de tous les écrans d'ARCHITECTURE.md §7,
   bottom navigation Accueil / Recherche / Bibliothèque / Profil. [flutter-ui]
4. Riverpod + client Supabase configurés.
5. Migrations : table profiles + RLS + trigger de création auto du profil à
   l'inscription ; table genres pré-remplie (seed). [db-architect]
6. Auth complète : inscription email (avec vérification), connexion, Google
   Sign-In (Android + web), mot de passe oublié, déconnexion, garde de
   routes (redirection si non connecté). [flutter-ui + toi]
7. Écran profil : affichage + édition (display_name, bio, avatar).
8. CI GitHub Actions : analyze + tests + build web sur chaque push.
9. Tests : mappers, providers auth (mocks), widgets des écrans auth dans les
   deux thèmes, intégration inscription→connexion. [test-writer]
10. Audit final. [security-reviewer]

Critères de réussite :
- flutter analyze : 0 erreur ; tous les tests verts ; CI verte sur la PR.
- Je peux créer un compte, recevoir l'email de vérification, me connecter
  par email ET par Google, sur Android ET sur Chrome.
- Le switch de thème fonctionne et persiste après redémarrage.
- En base : le profil est créé automatiquement, et je ne peux pas lire/
  modifier le profil d'un autre utilisateur (test RLS à me montrer).

Vérification graphique (à faire toi-même avant de me rendre la main) :
- Lancer l'app sur Chrome, parcourir chaque écran dans les DEUX thèmes,
  vérifier : aucun overflow, boutons cliquables, champs de formulaire
  utilisables, messages d'erreur affichés (mauvais mot de passe, email
  invalide), état de chargement visible pendant la connexion.
- Me lister ce que tu as vérifié et toute anomalie restante.
```
