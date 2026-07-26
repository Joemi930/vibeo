import 'package:flutter/foundation.dart';

/// Journalise une erreur technique **en développement uniquement**.
///
/// Malgré son nom, `debugPrint` de Flutter s'exécute aussi en profile et en
/// release : sans ce garde-fou, le message brut d'une `PostgrestException`
/// (nom de la politique RLS violée, colonnes, contraintes) atterrirait dans la
/// console du navigateur d'un utilisateur en production — une carte du schéma
/// offerte à qui ouvre les outils de développement.
///
/// C'est l'unique porte de sortie des logs techniques de l'app : tout `catch`
/// qui veut tracer une erreur passe par ici, jamais par `debugPrint` direct.
/// L'utilisateur, lui, ne voit que le message en clair renvoyé par l'appelant.
///
/// Ce qui est visible en release passe par l'interface, pas par ce journal :
/// le lecteur, par exemple, expose la cause brute d'un échec derrière
/// « Détails techniques » (voir `PlaybackState.technicalDetail`).
void logError(String context, Object error, [StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('Vibeo — $context : $error');
  if (stack != null) debugPrint('$stack');
}
