import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/email_verification_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../widgets/main_scaffold.dart';
import '../widgets/placeholder_screen.dart';
import 'app_routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Fournit l'instance [GoRouter] de l'app, avec garde d'authentification.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(isAuthenticatedProvider);
      final loc = state.matchedLocation;
      final onAuthArea =
          loc == AppRoutes.auth || loc.startsWith('${AppRoutes.auth}/');

      // Non connecté hors zone auth → redirection vers l'écran de connexion.
      if (!loggedIn && !onAuthArea) return AppRoutes.auth;

      // Connecté sur l'écran de connexion → redirection vers l'accueil.
      if (loggedIn && loc == AppRoutes.auth) return AppRoutes.home;

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailVerification,
        builder: (context, state) => EmailVerificationScreen(
          email: state.extra is String ? state.extra as String : null,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search,
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.library,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      // Squelettes navigables (implémentés dans les phases suivantes).
      GoRoute(
        path: AppRoutes.studio,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Studio',
          icon: Icons.video_settings_rounded,
          phase: 'Phase 2',
        ),
      ),
      GoRoute(
        path: AppRoutes.upload,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Publier un clip',
          icon: Icons.upload_rounded,
          phase: 'Phase 2',
        ),
      ),
      GoRoute(
        path: AppRoutes.player,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Lecteur',
          icon: Icons.play_circle_outline_rounded,
          phase: 'Phase 2',
        ),
      ),
      GoRoute(
        path: AppRoutes.artist,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Artiste',
          icon: Icons.person_pin_rounded,
          phase: 'Phase 3',
        ),
      ),
      GoRoute(
        path: AppRoutes.becomeArtist,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Devenir artiste',
          icon: Icons.verified_rounded,
          phase: 'Phase 4',
        ),
      ),
      GoRoute(
        path: AppRoutes.applicationStatus,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Statut de candidature',
          icon: Icons.hourglass_top_rounded,
          phase: 'Phase 4',
        ),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const PlaceholderScreen(
          title: 'Administration',
          icon: Icons.admin_panel_settings_rounded,
          phase: 'Phase 6',
        ),
      ),
    ],
  );
});

/// Rafraîchit le router à chaque changement d'état d'authentification.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _sub = _ref.listen(authStateChangesProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
