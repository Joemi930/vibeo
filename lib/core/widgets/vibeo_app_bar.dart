import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_routes.dart';
import 'theme_toggle_switch.dart';

/// Barre supérieure commune à tous les écrans.
///
/// Deux besoins transverses y sont centralisés :
/// 1. un **bouton retour** en haut à gauche sur chaque page hors accueil ;
/// 2. l'**interrupteur de thème** clair ↔ sombre, pour ne pas avoir à passer
///    par les Paramètres.
///
/// Le retour utilise `context.pop()` quand la pile de navigation le permet, et
/// retombe sinon sur [fallbackRoute] : indispensable sur le web, où l'on peut
/// arriver directement sur une page par un lien partagé ou un rechargement,
/// sans historique interne.
class VibeoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VibeoAppBar({
    this.title,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.fallbackRoute = AppRoutes.home,
    this.showThemeToggle = true,
    this.bottom,
    super.key,
  });

  /// Titre affiché ; `null` pour une barre sans titre.
  final String? title;

  /// Actions ajoutées AVANT l'interrupteur de thème.
  final List<Widget> actions;

  /// `false` uniquement sur l'accueil, qui est la racine de la navigation.
  final bool showBack;

  /// Destination de repli quand il n'y a rien à dépiler.
  final String fallbackRoute;

  final bool showThemeToggle;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Retour',
              onPressed: () => popOrGo(context, fallbackRoute),
            )
          : null,
      title: title == null ? null : Text(title!),
      actions: [
        ...actions,
        if (showThemeToggle) const ThemeToggleSwitch(),
        const SizedBox(width: 4),
      ],
      bottom: bottom,
    );
  }

  /// Revient en arrière si possible, sinon rejoint [fallback].
  ///
  /// Exposé pour que les écrans sans [AppBar] (lecteur, page artiste, où la
  /// flèche est posée sur le média) partagent exactement le même comportement.
  ///
  /// On interroge d'abord le [Navigator] plutôt que go_router : c'est valable
  /// pour un écran empilé comme pour un onglet du shell (dont la racine n'a
  /// rien à dépiler, d'où le repli sur [fallback]), et cela laisse le widget
  /// utilisable dans un test sans routeur.
  static void popOrGo(
    BuildContext context, [
    String fallback = AppRoutes.home,
  ]) {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(fallback);
  }
}
