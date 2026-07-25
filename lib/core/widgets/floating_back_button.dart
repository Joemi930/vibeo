import 'package:flutter/material.dart';

import '../router/app_routes.dart';
import 'vibeo_app_bar.dart';

/// Flèche de retour posée par-dessus un média (lecteur, bannière artiste).
///
/// Ces écrans n'ont pas d'[AppBar] : la maquette place la flèche directement
/// sur la vidéo ou la bannière. Le comportement de retour reste identique à
/// celui de [VibeoAppBar] (dépiler si possible, sinon rejoindre l'accueil).
class FloatingBackButton extends StatelessWidget {
  const FloatingBackButton({
    this.fallbackRoute = AppRoutes.home,
    this.size = 26,
    super.key,
  });

  final String fallbackRoute;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(Icons.arrow_back_rounded, size: size),
        color: Colors.white,
        tooltip: 'Retour',
        onPressed: () => VibeoAppBar.popOrGo(context, fallbackRoute),
      ),
    );
  }
}
