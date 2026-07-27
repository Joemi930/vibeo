import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../video/domain/video.dart';
import '../../data/discovery_repository.dart';

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  return SupabaseDiscoveryRepository(ref.watch(supabaseClientProvider));
});

/// Section « Tendances » de l'accueil.
///
/// `keepAlive` empêche Riverpod 3 de détruire et reconstruire la liste au
/// retour d'une lecture : sans lui, un aller-retour de deux minutes déclenchait
/// trois appels réseau pour rien. L'invalidation se fait par `RefreshIndicator`
/// et par les mutations — pas par un minuteur.
final trendingVideosProvider = FutureProvider<List<Video>>((ref) {
  ref.keepAlive();
  return ref.watch(discoveryRepositoryProvider).fetchTrending();
});

/// Section « Recommandé pour toi ».
///
/// Volontairement sans famille ni paramètre d'utilisateur : la base déduit
/// l'identité du jeton. Un invité reçoit les tendances, ce qui est traité côté
/// SQL — l'accueil n'a donc pas à distinguer les deux cas.
final recommendedVideosProvider = FutureProvider<List<Video>>((ref) {
  ref.keepAlive();
  return ref.watch(discoveryRepositoryProvider).fetchRecommended();
});

/// Tendances d'un genre précis, pour l'écran « Tout voir ».
final trendingByGenreProvider = FutureProvider.family<List<Video>, int?>((
  ref,
  genreId,
) {
  return ref
      .watch(discoveryRepositoryProvider)
      .fetchTrending(limit: 60, genreId: genreId);
});
