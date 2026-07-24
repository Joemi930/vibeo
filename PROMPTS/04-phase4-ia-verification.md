# PROMPT PHASE 4 — IA : vérification d'artistes + modération (mode plan)

```
PHASE 4 : l'IA au service de la confiance. Zone LA PLUS SENSIBLE du projet
(documents d'identité). Plan d'abord, attends ma validation.

Contenu :
1. Migrations : artist_applications (avec id_document_path), moderation_logs,
   bucket privé identity-docs (lecture admins uniquement), cron pg de
   suppression des documents décidés (30 j max), rate limiting 1
   candidature/semaine. [db-architect]
2. Module supabase/functions/_shared/ai-provider.ts : abstraction
   analyzeText()/analyzeImage(), implémentation Gemini (défaut) + DeepSeek
   (texte seul), sélection par AI_PROVIDER. Vérifie les noms de modèles
   actuels dans la doc officielle Gemini avant d'implémenter. [toi]
3. Edge Function verify-artist : validation Zod, analyse du dossier + carte
   d'identité selon docs/ARCHITECTURE.md §4 (score, seuils 80/30,
   manual_review entre les deux), écriture moderation_logs. [toi, audit
   renforcé ensuite]
4. Edge Function moderate-video : à l'upload, statut pending_moderation →
   analyse titre + description + miniature → published auto ou file admin
   + motif. [toi]
5. Edge Function process-report : priorisation des signalements. [toi]
6. UI "Devenir artiste" : formulaire, upload du document (photo/scan avec
   cadrage), consentement explicite ("document supprimé après décision"),
   écran de suivi du statut. [flutter-ui]
7. Adapter le Studio : bandeau de statut des vidéos (en modération/rejetée
   avec motif). [flutter-ui]
8. Tests : ai-provider mocké (jamais d'appel réel en test), logique de
   seuils, Edge Functions (deno test), widgets candidature deux thèmes,
   intégration candidature complète. [test-writer]
9. AUDIT COMPLET obligatoire : identity-docs inaccessible hors admin, URLs
   signées 5 min, suppression auto opérationnelle, aucune donnée du document
   en base, clés IA absentes du client et du repo. [security-reviewer]

Critères de réussite :
- Compte test : je candidate avec un document → le statut évolue ; un score
  moyen atterrit en manual_review ; les logs de modération tracent tout.
- Depuis un compte non-admin, TOUTE tentative d'accès au bucket
  identity-docs échoue (montre-moi les tests).
- Une vidéo au titre problématique part en file admin au lieu d'être publiée.
- supabase secrets list montre les clés ; grep du repo : aucune clé en dur.

Vérification graphique :
- Formulaire de candidature deux thèmes : upload avec aperçu, messages
  d'erreur (fichier trop lourd, format invalide), écran de suivi lisible,
  états du Studio (badges de statut colorés accessibles). Liste vérifiée.
```
