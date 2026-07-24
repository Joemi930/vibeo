# PROMPT PHASE 6 — Admin, durcissement, livraison (mode plan)

```
PHASE 6 (finale) : dashboard admin + sécurité globale + livraison. Plan
d'abord, attends ma validation.

Contenu :
1. Dashboard admin (web prioritaire, responsive) : file des candidatures
   manual_review avec rapport IA + visionneuse sécurisée du document (URL
   5 min), file de modération vidéos, gestion des signalements (actions :
   retirer, avertir, ignorer), stats globales (utilisateurs, vidéos, vues,
   usage storage vs limite 1 Go), journal moderation_logs filtrable.
   [flutter-ui + db-architect pour les vues stats]
2. Garde de route admin stricte (rôle vérifié serveur ET client). [toi]
3. Durcissement web : vercel.json avec CSP, X-Frame-Options, HSTS ;
   configuration CORS des buckets. [toi]
4. Gitleaks en CI + revue du .gitignore. [toi]
5. Campagne de tests d'intégration finale : tous les parcours critiques
   bout en bout listés dans CLAUDE.md. [test-writer]
6. AUDIT GLOBAL FINAL : repasser TOUTE la checklist du security-reviewer
   sur l'ensemble du code, pas seulement le diff. Traiter tous les findings
   CRITIQUE et ÉLEVÉ avant livraison. [security-reviewer]
7. Livraison : build APK release signé (guide de signature pour moi),
   déploiement Vercel du build web, README.md complet (présentation,
   captures, stack, lancement local) — c'est la vitrine portfolio.
8. docs/ : mettre à jour ARCHITECTURE.md avec l'état final réel + un
   POSTMORTEM.md court (ce qui a changé vs le plan initial et pourquoi).

Critères de réussite :
- Un compte admin fait TOUT le tour : valide une candidature, rejette une
  vidéo, traite un signalement — chaque action tracée dans le journal.
- Un compte non-admin qui force l'URL /admin est rejeté (client ET serveur).
- securityheaders.com donne au moins un A- sur l'URL Vercel.
- CI verte, gitleaks vert, tous les tests verts, flutter analyze 0 erreur.
- J'installe l'APK sur mon téléphone et je déroule le parcours complet
  utilisateur ET artiste sans crash.

Vérification graphique :
- Dashboard admin au clavier ET à la souris, deux thèmes, tableaux lisibles
  en mobile (colonnes prioritaires), confirmations avant actions
  destructives, badge d'usage storage visible. Liste-moi ce qui a été
  vérifié + captures d'écran des écrans clés dans le rapport final.
```
