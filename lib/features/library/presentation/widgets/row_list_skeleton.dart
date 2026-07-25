import 'package:flutter/material.dart';

import '../../../../core/widgets/skeleton_box.dart';

/// Squelette d'une ligne de playlist (vignette carrée 56 px + deux lignes de
/// texte), calqué sur `Maquettes/SkeletonLibrary.dc.html`.
///
/// Le squelette générique de liste (`RowListSkeleton`) vit dans
/// `core/widgets` : partagé par la Bibliothèque et la Recherche.
class PlaylistRowSkeleton extends StatelessWidget {
  const PlaylistRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SkeletonBox(
            width: 56,
            height: 56,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.55,
                  child: SkeletonBox(height: 15),
                ),
                const SizedBox(height: 8),
                const FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.35,
                  child: SkeletonBox(height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
