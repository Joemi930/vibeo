import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../router/app_routes.dart';

/// Construction des liens partageables vers l'application web.
///
/// L'application web utilise le routage par **fragment** (`/#/video/<id>`) :
/// c'est ce qui lui permet d'être servie comme un site statique sur Vercel,
/// sans règle de réécriture côté serveur. Les liens partagés doivent donc
/// porter ce `#`, sans quoi ils tomberaient sur une 404.
class ShareLinks {
  const ShareLinks._();

  /// Racine du site.
  ///
  /// Sur le web, l'origine réelle de la page l'emporte : le lien reste valable
  /// que l'app tourne en local, en préproduction ou en production, sans
  /// reconfiguration. Sur Android, il faut la valeur fournie à la compilation.
  static String? get baseUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null') return origin;
    }
    final configured = Env.webBaseUrl.trim();
    if (configured.isEmpty) return null;
    return configured.endsWith('/')
        ? configured.substring(0, configured.length - 1)
        : configured;
  }

  /// Lien public vers le lecteur d'un clip, ou `null` si aucune adresse de
  /// site n'est connue.
  static String? video(String videoId) {
    final base = baseUrl;
    if (base == null) return null;
    return '$base/#${AppRoutes.video(videoId)}';
  }

  /// Lien public vers la page d'un artiste.
  static String? artist(String artistId) {
    final base = baseUrl;
    if (base == null) return null;
    return '$base/#${AppRoutes.artist(artistId)}';
  }

  /// Texte de partage d'un clip, lien compris quand il est disponible.
  static String videoMessage({
    required String videoId,
    required String title,
    String? artistName,
  }) {
    final who = artistName == null || artistName.isEmpty
        ? ''
        : ' par $artistName';
    final link = video(videoId);
    final intro = 'Découvre « $title »$who sur Vibeo.';
    return link == null ? intro : '$intro\n$link';
  }
}
