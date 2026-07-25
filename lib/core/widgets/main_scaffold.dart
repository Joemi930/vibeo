import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/presentation/widgets/mini_player.dart';

/// Ossature principale de l'app : barre de navigation basse à 4 onglets
/// (Accueil / Recherche / Bibliothèque / Profil), avec état préservé par onglet
/// grâce à [StatefulNavigationShell].
///
/// Le mini-player persistant s'intercale entre le contenu et la barre de
/// navigation : comme il lit son état d'un provider vivant à la racine, la
/// lecture survit au changement d'onglet. Le lecteur plein écran étant empilé
/// sur le navigateur racine, le mini-player disparaît naturellement quand il
/// est ouvert.
class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search_rounded),
                label: 'Recherche',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Bibliothèque',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
