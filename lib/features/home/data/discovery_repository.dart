import 'package:supabase_flutter/supabase_flutter.dart';

import '../../video/domain/video.dart';

/// Accès aux sections de découverte de l'accueil : tendances et recommandations.
///
/// Séparé de `VideoRepository` parce que ces deux listes ne sont pas des
/// requêtes sur `videos` : ce sont des fonctions SQL qui font le classement en
/// base. Le reproduire côté client obligerait à rapatrier tout le catalogue.
///
/// L'abstraction sert de couture de test, comme partout ailleurs dans le projet.
abstract class DiscoveryRepository {
  /// Clips en tendance sur les sept derniers jours.
  ///
  /// Le classement vient de la vue matérialisée `trending_videos`, rafraîchie
  /// toutes les heures. Mais la vue **n'est pas lue directement** : la fonction
  /// SQL rejoint `videos` et revérifie le statut à chaque appel, de sorte qu'un
  /// clip retiré par la modération disparaît immédiatement des tendances, sans
  /// attendre le rafraîchissement suivant.
  Future<List<Video>> fetchTrending({int limit = 20, int? genreId});

  /// Clips recommandés pour l'utilisateur connecté.
  ///
  /// L'identité n'est **pas** un paramètre : elle vient de `auth.uid()` côté
  /// base. Un paramètre laisserait n'importe qui demander les recommandations —
  /// donc le profil d'écoute — de quelqu'un d'autre.
  ///
  /// Un compte neuf ou un invité reçoit exactement les tendances : c'est le
  /// démarrage à froid, traité en base et non ici.
  Future<List<Video>> fetchRecommended({int limit = 20});
}

class SupabaseDiscoveryRepository implements DiscoveryRepository {
  SupabaseDiscoveryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Video>> fetchTrending({int limit = 20, int? genreId}) async {
    final rows = await _client.rpc(
      'trending_videos_feed',
      params: {'p_limit': limit, 'p_genre_id': genreId},
    );
    return _parse(rows);
  }

  @override
  Future<List<Video>> fetchRecommended({int limit = 20}) async {
    final rows = await _client.rpc(
      'recommended_videos',
      params: {'p_limit': limit},
    );
    return _parse(rows);
  }

  List<Video> _parse(dynamic rows) {
    if (rows is! List) return const [];
    return rows
        .cast<Map<String, dynamic>>()
        .map<Video>(Video.fromJson)
        .toList();
  }
}
