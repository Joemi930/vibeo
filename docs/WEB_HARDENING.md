# Durcissement du déploiement web

Ce qui est en place dans `vercel.json`, pourquoi chaque directive y est, et ce
qu'il reste à vérifier **à la main** après déploiement.

## Politique de sécurité de contenu — les choix qui comptent

### `'wasm-unsafe-eval'` dans `script-src`

CanvasKit, le moteur de rendu de Flutter web, est du WebAssembly. Compiler du
WASM dans une page sous CSP exige `'unsafe-eval'` ou, plus étroitement,
`'wasm-unsafe-eval'`. Nous prenons le second.

**Limitation assumée : Safari antérieur à 16.4 ignore `'wasm-unsafe-eval'`** et
refusera donc de charger l'application. L'alternative serait `'unsafe-eval'`,
qui autoriserait aussi `eval()` sur du JavaScript arbitraire — c'est-à-dire le
vecteur d'exploitation le plus courant d'une faille d'injection. Nous
préférons perdre Safari 15 que rouvrir `eval`.

### `script-src 'self'` sans `'unsafe-inline'`, grâce à deux mesures

1. **`flutter build web --csp`** produit un bundle sans script en ligne ni
   `eval` dans `main.dart.js`. Sans ce drapeau, la politique casse l'application.
   Il est posé dans `vercel.json` (`buildCommand`) **et** dans la CI — les deux,
   parce qu'un build produit par un chemin non durci passerait inaperçu.
2. **CanvasKit est auto-hébergé** via `web/flutter_bootstrap.js`
   (`canvasKitBaseUrl: 'canvaskit/'`). Par défaut, Flutter le charge depuis
   `gstatic.com` : il faudrait alors autoriser un hôte tiers à exécuter du code
   dans notre page.

### `style-src 'unsafe-inline'` — incontournable

Flutter web écrit des styles en ligne pour positionner ses vues plateforme. Il
n'existe pas de moyen de l'en empêcher. C'est le point faible connu et assumé
de la politique ; il est nettement moins grave que `script-src 'unsafe-inline'`.

### `blob:` dans `script-src`, `worker-src` et `child-src`

Requis par les *workers* WebCodecs de `mediabunny`, qui font la compression 720p
dans le navigateur. Sans cela, la publication d'un clip depuis le web échoue.

### `fonts.googleapis.com` / `fonts.gstatic.com`

Le paquet `google_fonts` télécharge Plus Jakarta Sans au démarrage.

**Amélioration identifiée, non faite :** embarquer la police en asset
supprimerait ces deux hôtes de la politique et ferait fonctionner l'application
hors ligne. C'est d'ailleurs déjà ce que supposent les tests, qui posent
`GoogleFonts.config.allowRuntimeFetching = false`. Non fait ici parce que cela
suppose de télécharger et committer les fichiers de police — à décider par le
propriétaire du projet.

### `Cross-Origin-Opener-Policy: same-origin-allow-popups`

**C'est la directive qui casse la connexion Google si on se trompe.** La valeur
« évidente » `same-origin` ferme la fenêtre surgissante d'authentification :
l'utilisateur voit un écran Google s'ouvrir puis disparaître, sans message.
`same-allow-popups` conserve l'isolation tout en laissant la fenêtre
communiquer avec la page qui l'a ouverte.

## Ce que la spécification demandait et qui n'a pas lieu d'être

Le prompt de Phase 6 demandait « configuration CORS des buckets ». **Supabase
Storage n'expose pas de réglage CORS par bucket** : il est défini au niveau du
projet et vaut `*` par défaut. Il n'y a donc rien à configurer. Ce qui compte
réellement, et qui est fait, c'est que le domaine du projet Supabase figure dans
`img-src`, `media-src` et `connect-src` — sans quoi miniatures et vidéos
seraient bloquées par notre propre politique.

## La clé Supabase visible dans le bundle — c'est voulu

`flutter build web` incruste `SUPABASE_ANON_KEY` dans `main.dart.js`, et elle
est donc lisible par n'importe qui. **Ce n'est pas une fuite.** Cette clé est
publiable par conception : elle identifie le projet, elle n'autorise rien par
elle-même. Ce sont les politiques RLS de Postgres — et elles seules — qui
décident de ce que chaque appelant peut lire ou écrire.

La clé qui ne doit jamais approcher le client est `service_role`, qui contourne
toute la RLS. Elle vit uniquement dans les secrets des Edge Functions, et
`.gitleaks.toml` prend soin de **ne pas** l'inclure dans ses exclusions.

## À vérifier manuellement après le premier déploiement

Ces points ne peuvent pas être vérifiés depuis le dépôt.

1. **La connexion Google fonctionne.** C'est le premier élément à casser sous
   une CSP. Si la fenêtre s'ouvre et se referme aussitôt, regarder la console :
   une violation `frame-src` ou un blocage COOP y apparaîtra.
2. **La lecture vidéo fonctionne** : les URL signées Supabase doivent passer
   `media-src`.
3. **La publication depuis le web fonctionne** : c'est le chemin qui exerce les
   *workers* `blob:`.
4. **`securityheaders.com`** sur l'URL de production — objectif A-.
5. **Le rendu n'est pas cassé** : si l'écran reste blanc, la cause est presque
   toujours CanvasKit bloqué. La console indique alors la directive fautive.
