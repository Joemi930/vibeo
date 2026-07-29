# Post-mortem — ce qui a changé par rapport au plan initial, et pourquoi

Ce document existe pour une raison précise : un plan d'architecture écrit avant
de coder se trompe toujours quelque part, et l'écart est plus instructif que le
plan. Chaque point ci-dessous est un endroit où la réalité a contredit
`ARCHITECTURE.md` ou les prompts de phase. Aucun n'est un oubli — tous sont des
décisions, avec leur raison.

---

## 1. Les documents d'identité ne sont lisibles par personne, pas même par les admins

**Prévu** (`ARCHITECTURE.md` §4) : « bucket `identity-docs` : accès en lecture
UNIQUEMENT aux admins (RLS storage) ».

**Livré** : le bucket n'a **aucune politique de lecture, ni de suppression**.

Une politique `bucket_id = 'identity-docs' and is_admin()` signifie qu'un jeton
d'administrateur volé permet de **lister et télécharger toutes les pièces
d'identité** directement depuis l'API Storage, sans laisser de trace. Sans
politique de lecture, seul `service_role` accède aux fichiers — c'est-à-dire
deux Edge Functions auditées, dont l'une journalise nominativement chaque
consultation et n'émet que des URL de cinq minutes.

C'est strictement plus fort que ce qui était prévu, et cohérent avec la décision
déjà prise en Phase 3.5 pour `user_identities`, laissée sans politique admin
pour exactement la même raison.

Conséquence assumée : même le propriétaire ne peut pas relire son document.
L'aperçu du formulaire de candidature est donc rendu depuis les octets locaux,
jamais depuis le serveur.

## 2. La purge des documents ne peut pas être faite en SQL

**Prévu** (prompt de Phase 4) : « cron pg de suppression des documents décidés ».

**Livré** : `pg_cron` déclenche, via `pg_net`, une Edge Function
`purge-identity-docs`.

La première rédaction faisait bien la purge en SQL — et c'était faux d'une
manière dangereuse. **Supprimer une ligne de `storage.objects` retire l'entrée
du catalogue mais ne supprime pas le fichier.** On obtenait un blob orphelin qui
consomme le quota pour toujours, pendant que la base affirmait, via
`document_purged_at`, que la pièce d'identité avait été effacée.

Une trace d'audit mensongère sur une donnée d'identité est pire que pas de trace
du tout : elle empêche de découvrir le problème. La suppression réelle exige
l'API Storage, donc du HTTP, donc une Edge Function. Celle-ci ne marque
`document_purged_at` **que si la suppression a réellement abouti**.

## 3. `process-report` n'existe pas ; la priorité est calculée en SQL

**Prévu** (`ARCHITECTURE.md` §5) : une Edge Function IA de priorisation des
signalements.

**Livré** : une colonne `reports.priority`, calculée par le trigger existant à
l'insertion.

L'IA n'a rien à dire d'utile sur un motif choisi dans une liste fermée. Le tri
utile — gravité du motif, nombre de signalements sur la même cible, récidive de
l'auteur — est de l'arithmétique. La faire en base coûte zéro appel réseau,
zéro clé, et est entièrement testable. La spécification demandait « priorisation
des signalements » : c'est littéralement ce qui est livré, sans la troisième
surface d'IA à surveiller.

**Bug trouvé pendant la vérification, et instructif** : le calcul interrogeait
`reports` et `moderation_logs` depuis une fonction `SECURITY INVOKER`. Or
`reports` n'a pas de politique de lecture pour son auteur et `moderation_logs`
est réservée aux admins : ces `count(*)` renvoyaient donc silencieusement zéro
et la priorité ne montait jamais. Corrigé par un helper `SECURITY DEFINER` qui
n'expose qu'un entier agrégé. Un bug qu'aucune relecture n'aurait vu et que
seule l'exécution réelle du test a révélé.

## 4. `report_status` n'a pas gagné la valeur `actioned`

**Prévu** (`ARCHITECTURE.md` §3) : `open | reviewed | actioned | dismissed`.
**Livré** : `pending | reviewed | dismissed`, inchangé depuis la Phase 3.

Deux raisons. D'abord une contrainte technique : `alter type … add value` ne
peut pas être suivi d'un usage de la nouvelle valeur dans la même transaction,
et la CLI Supabase enveloppe chaque migration dans une transaction — il faudrait
un fichier isolé pour une valeur d'énumération.

Ensuite, c'est inutile : les trois actions demandées (retirer, avertir, ignorer)
se projettent proprement sur `reviewed` ou `dismissed`, **plus une ligne de
`moderation_logs`**. Le *où en est-on* vit dans le statut, le *quoi* dans le
journal. Séparer les deux est plus juste que de les fondre dans une énumération.

## 5. Aucune action de modération ne passe par le client Supabase

Découverte structurante, faite avant d'écrire l'interface admin : le trigger
`videos_guard_client_fields()` interdit les statuts de modération à tout rôle
autre que `service_role`. Or **un administrateur connecté est `authenticated`**.

Ajouter une politique `videos_update_admin` serait donc vain : elle serait
incapable de faire la seule chose pour laquelle elle existerait. Toutes les
actions admin passent par la fonction `admin-actions`, qui relit le rôle en base
avec la clé `service_role` — jamais depuis une revendication du jeton, qu'un
administrateur rétrogradé porterait encore jusqu'à son expiration.

## 6. Le verrou de publication est plus strict que prévu

Le plan prévoyait de retirer `published` des statuts autorisés à la création.
En l'écrivant, un second trou est apparu : l'ancienne règle ne bloquait que les
transitions **vers** un statut de modération. Un artiste dont le clip était
`rejected` pouvait donc le repasser lui-même en `published` — le rejet était
annulable d'un clic par la personne sanctionnée.

Le client n'a désormais plus aucune maîtrise du statut, dans aucun sens, ni de
`moderation_result` (qui porte le motif affiché : il se le serait réécrit). Un
test dédié vérifie que la modification légitime du titre, de la description et
de la miniature fonctionne toujours — sans quoi le verrou aurait cassé le Studio.

## 7. La vue matérialisée des tendances n'est exposée à personne

**Prévu** (prompt de Phase 5) : « vue matérialisée `trending_videos` rafraîchie
par cron ».

C'est fait, mais **une vue matérialisée ne porte pas de RLS**. L'exposer
directement laisserait une vidéo retirée par la modération visible en tendances
jusqu'au rafraîchissement suivant — jusqu'à une heure d'exposition d'un contenu
qu'on vient précisément de retirer.

La vue ne contient donc que des identifiants et des scores, et n'est accessible
à aucun rôle applicatif. L'accès public passe par des fonctions qui rejoignent
`public.videos` et revérifient `status = 'published'` à chaque appel. Un test
vérifie qu'une vidéo passée en `removed` disparaît **immédiatement**, sans
rafraîchissement.

## 8. La vérification IA a été retirée (Phase 7)

La vérification IA des candidatures a été entièrement retirée à la Phase 7.
Toute candidature valide est désormais approuvée automatiquement après les
contrôles de base (doublon, rate limit, validité du document). La fiabilité
insuffisante de l'IA sur les documents d'identité (trop de faux positifs) et
la complexité opérationnelle (gestion des clés, coûts) ne justifiaient pas
son maintien pour un projet de cette taille.

## 9. Il n'y a pas de CORS de bucket à configurer

**Prévu** (prompt de Phase 6) : « configuration CORS des buckets ».

Supabase Storage n'expose pas de réglage CORS par bucket : il est défini au
niveau du projet et vaut `*`. Il n'y avait rien à faire. Ce qui compte
réellement, et qui est fait, c'est que le domaine du projet figure dans
`img-src`, `media-src` et `connect-src` de la politique de sécurité de contenu —
sans quoi l'application se bloquerait elle-même.

## 10. Ce qui reste à faire

**Reporté, explicitement, pas oublié :**

- **Durcissement du compteur de vues.** `ARCHITECTURE.md` annonçait, pour la
  Phase 4, un jeton de lecture signé remplaçant la `session_key` fournie par le
  client. Non fait. `record_view` reste appelable par `anon` avec une clé de
  session choisie par l'appelant : un script peut gonfler `view_count`. Cela
  affecte le classement des tendances, donc la vitrine — pas la sécurité des
  données.
- **Police embarquée en asset.** `google_fonts` télécharge Plus Jakarta Sans au
  démarrage, ce qui oblige à autoriser deux hôtes Google dans la politique de
  sécurité. L'embarquer supprimerait ces exceptions et ferait fonctionner
  l'application hors ligne.
- **Safari antérieur à 16.4** ne charge pas l'application : il ignore
  `'wasm-unsafe-eval'`, indispensable à CanvasKit. L'alternative serait
  d'autoriser `'unsafe-eval'` tout court, ce qui rouvrirait le vecteur
  d'injection le plus courant. Arbitrage assumé.
- **Un projet Supabase gratuit est mis en pause après 7 jours d'inactivité.** Le
  planificateur s'arrête avec lui : tendances figées, purges non exécutées. À
  savoir avant une démonstration après une longue pause.
