// Amorçage Flutter personnalisé.
//
// Une seule raison d'exister : **auto-héberger CanvasKit**.
//
// Par défaut, Flutter va chercher le moteur de rendu sur
// `https://www.gstatic.com/flutter-canvaskit/<révision>/`. Cela obligerait à
// autoriser `gstatic.com` dans `script-src` ET `connect-src` de notre politique
// de sécurité de contenu — c'est-à-dire à faire confiance à un hôte tiers pour
// exécuter du code dans notre page. `flutter build web` copie déjà CanvasKit
// dans `build/web/canvaskit/` : il suffit de lui dire de s'en servir.
//
// Les accolades doubles sont des jetons remplacés par `flutter build web`.
// Ne pas les toucher.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Chemin relatif : fonctionne aussi bien à la racine du domaine que sous
    // un sous-chemin (`--base-href`).
    canvasKitBaseUrl: 'canvaskit/',
  },
});
