import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';

/// État avant toute recherche (moins de deux caractères saisis).
///
/// Distinct de [SearchNoResultsState] : ici, l'utilisateur n'a pas encore
/// vraiment cherché (voir consigne Phase 3 sur les deux états à séparer).
class SearchInitialState extends StatelessWidget {
  const SearchInitialState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_rounded,
      title: 'Trouve un clip ou un artiste',
      message: message,
    );
  }
}

/// État « aucun résultat » pour une requête précise et actionnable, calqué
/// sur `Maquettes/SearchEmpty.dc.html`.
class SearchNoResultsState extends StatelessWidget {
  const SearchNoResultsState({
    required this.query,
    required this.onClear,
    super.key,
  });

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'Aucun résultat pour « $query »',
      message:
          "Vérifie l'orthographe ou essaie un autre nom d'artiste, de clip "
          'ou de genre.',
      actionLabel: 'Effacer la recherche',
      onAction: onClear,
    );
  }
}
