import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Insigne « artiste vérifié » affiché juste après le nom d'un artiste.
///
/// Glyphe Material `verified` rempli, dans la variante de la primaire
/// (`VibeoColors.verified`). La taille s'adapte au contexte : ~13 px sous une
/// carte de clip, ~15 px dans le lecteur, ~20 px en en-tête de page artiste.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({this.size = 15, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Artiste vérifié',
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: VibeoColors.of(context).verified,
        semanticLabel: 'Artiste vérifié',
      ),
    );
  }
}

/// Nom d'artiste suivi, le cas échéant, de son insigne de vérification.
///
/// Évite de répéter le couple `Text` + [VerifiedBadge] dans chaque écran.
class ArtistNameLabel extends StatelessWidget {
  const ArtistNameLabel({
    required this.name,
    required this.isVerified,
    this.style,
    this.badgeSize = 13,
    super.key,
  });

  final String name;
  final bool isVerified;
  final TextStyle? style;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            style: style ?? Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isVerified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(size: badgeSize),
        ],
      ],
    );
  }
}
