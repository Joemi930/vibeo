import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bouton « S'abonner » / « Abonné », partagé par la ligne artiste du lecteur
/// et la page artiste publique.
///
/// Bascule immédiatement : c'est l'appelant qui porte l'affichage optimiste
/// (voir `SubscribeController`), ce bouton ne fait qu'en refléter l'état.
class SubscribeButton extends StatelessWidget {
  const SubscribeButton({
    required this.isSubscribed,
    required this.isBusy,
    required this.onPressed,
    this.expand = false,
    super.key,
  });

  final bool isSubscribed;
  final bool isBusy;
  final VoidCallback onPressed;

  /// `true` pour occuper toute la largeur disponible (page artiste).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = isSubscribed
        ? _subscribed(context)
        : _notSubscribed(context);
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _subscribed(BuildContext context) {
    return Semantics(
      button: true,
      toggled: true,
      label: 'Se désabonner',
      child: OutlinedButton.icon(
        onPressed: isBusy ? null : onPressed,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text(
          'Abonné',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  Widget _notSubscribed(BuildContext context) {
    return Semantics(
      button: true,
      toggled: false,
      label: "S'abonner à cet artiste",
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: VibeoColors.of(context).gradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: isBusy ? null : onPressed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Text(
                "S'abonner",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
