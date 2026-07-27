import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/artist/presentation/application_status_screen.dart';
import '../../features/artist/presentation/artist_screen.dart';
import '../../features/artist/presentation/become_artist_screen.dart';
import '../../features/artist/presentation/providers/artist_application_providers.dart';
import '../../features/auth/domain/user_role.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/email_verification_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/providers/guest_mode_provider.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/library/presentation/playlist_screen.dart';
import '../../features/player/presentation/audio_mode_screen.dart';
import '../../features/player/presentation/player_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/providers/profile_providers.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/account_privacy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/studio/presentation/edit_video_screen.dart';
import '../../features/studio/presentation/studio_screen.dart';
import '../../features/upload/presentation/upload_flow_screen.dart';
import '../widgets/main_scaffold.dart';
import '../../features/admin/presentation/admin_shell.dart';
import 'app_routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Fournit l'instance [GoRouter] de l'app, avec garde d'authentification.
///
/// Trois règles cohabitent :
/// 1. **Invité** : sans session mais avec le mode invité actif, les routes
///    publiques (accueil, recherche, lecteur, page artiste) restent ouvertes.
/// 2. **Retour à l'endroit exact** : une redirection vers l'auth conserve la
///    destination dans `?returnTo=`, rejouée après connexion.
/// 3. **Rôle** : le studio et l'upload sont réservés aux artistes. Garde-fou
///    d'ergonomie seulement — la RLS reste la barrière réelle.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(isAuthenticatedProvider);
      final isGuest = ref.read(guestModeProvider);
      final loc = state.matchedLocation;
      final onAuthArea =
          loc == AppRoutes.auth || loc.startsWith('${AppRoutes.auth}/');

      // Connecté sur l'écran de connexion → on rejoint la destination
      // mémorisée, sinon l'accueil.
      if (loggedIn && loc == AppRoutes.auth) {
        return AppRoutes.sanitizeReturnTo(
          state.uri.queryParameters['returnTo'],
        );
      }

      if (loggedIn) {
        // Comptes d'administration : cantonnés au dashboard et aux paramètres.
        // Un admin qui arrive sur l'accueil ou toute autre route hors /admin
        // et /settings est redirigé vers le dashboard.
        final role = ref.read(currentRoleProvider);
        if (role == UserRole.admin &&
            !loc.startsWith(AppRoutes.admin) &&
            !loc.startsWith(AppRoutes.settings)) {
          return AppRoutes.admin;
        }

        // Studio et upload : réservés aux artistes. Tant que le profil n'est
        // pas chargé (rôle null), on laisse passer — l'écran affiche son propre
        // état de chargement et la redirection se fera au rafraîchissement.
        // `startsWith` couvre les écrans sous le Studio (modification d'un
        // clip) : une comparaison stricte les laisserait sans garde.
        if (loc.startsWith(AppRoutes.studio) || loc == AppRoutes.upload) {
          final role = ref.read(currentRoleProvider);
          if (role != null && role == UserRole.listener) {
            return AppRoutes.becomeArtist;
          }
        }

        // Administration : seuls les administrateurs passent. Quand le rôle
        // est encore inconnu (profil en cours de chargement), on redirige vers
        // l'accueil plutôt que de risquer un flash du dashboard. Le profil
        // chargé, `_AuthRefreshNotifier` rejoue la garde et laisse passer les
        // vrais admins.
        if (loc.startsWith(AppRoutes.admin)) {
          final role = ref.read(currentRoleProvider);
          if (role != UserRole.admin) {
            return AppRoutes.home;
          }
        }

        // Candidature artiste : inutile de remplir le formulaire si un rôle
        // artiste ou une candidature ouverte existe déjà. `asData?.value`
        // reste `null` tant que la requête n'a pas répondu — l'écran affiche
        // alors son propre chargement et refait la même vérification une
        // fois les données arrivées (voir `BecomeArtistScreen`).
        if (loc == AppRoutes.becomeArtist) {
          final role = ref.read(currentRoleProvider);
          if (role == UserRole.artist || role == UserRole.admin) {
            return AppRoutes.studio;
          }
          final application = ref.read(myApplicationProvider).asData?.value;
          if (application != null && application.status.isOpen) {
            return AppRoutes.applicationStatus;
          }
        }
        return null;
      }

      if (onAuthArea) return null;

      // Invité : les routes publiques restent accessibles, les autres renvoient
      // vers l'auth en mémorisant l'endroit d'où l'on vient.
      if (isGuest && AppRoutes.isPublic(loc)) return null;

      final returnTo = Uri.encodeComponent(state.uri.toString());
      return '${AppRoutes.auth}?returnTo=$returnTo';
    },
    routes: [
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) =>
            AuthScreen(returnTo: state.uri.queryParameters['returnTo']),
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
                routes: [
                  GoRoute(
                    path: AppRoutes.playlistSubPath,
                    builder: (context, state) => PlaylistScreen(
                      playlistId: state.pathParameters['playlistId']!,
                    ),
                  ),
                ],
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
      GoRoute(
        path: AppRoutes.accountPrivacy,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AccountPrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.studio,
        builder: (context, state) => const StudioScreen(),
      ),
      GoRoute(
        path: AppRoutes.editVideoPattern,
        builder: (context, state) =>
            EditVideoScreen(videoId: state.pathParameters['videoId'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.upload,
        builder: (context, state) => const UploadFlowScreen(),
      ),
      // Lecteur : c'est aussi la cible des liens de partage, donc accessible
      // sans compte (la RLS ne laisse voir que les clips publiés).
      GoRoute(
        path: AppRoutes.videoPattern,
        builder: (context, state) =>
            PlayerScreen(videoId: state.pathParameters['videoId']!),
      ),
      GoRoute(
        path: AppRoutes.audioPattern,
        builder: (context, state) =>
            AudioModeScreen(videoId: state.pathParameters['videoId']!),
      ),
      // Page publique d'un artiste — aussi accessible sans compte (RLS).
      GoRoute(
        path: AppRoutes.artistPattern,
        builder: (context, state) =>
            ArtistScreen(artistId: state.pathParameters['artistId']!),
      ),
      GoRoute(
        path: AppRoutes.becomeArtist,
        builder: (context, state) => const BecomeArtistScreen(),
      ),
      GoRoute(
        path: AppRoutes.applicationStatus,
        builder: (context, state) => const ApplicationStatusScreen(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminShell(),
      ),
    ],
  );
});

/// Rafraîchit le router à chaque changement d'état d'authentification.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(this._ref) {
    _authSub = _ref.listen(
      authStateChangesProvider,
      (_, _) => notifyListeners(),
    );
    _guestSub = _ref.listen(guestModeProvider, (_, _) => notifyListeners());
    // Le rôle arrive après le profil : il faut réévaluer la garde du studio.
    _roleSub = _ref.listen(currentRoleProvider, (_, _) => notifyListeners());
    // Idem pour la candidature artiste, résolue de façon asynchrone : la
    // garde de `/become-artist` doit se réévaluer dès qu'elle arrive.
    _applicationSub = _ref.listen(
      myApplicationProvider,
      (_, _) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription _authSub;
  late final ProviderSubscription _guestSub;
  late final ProviderSubscription _roleSub;
  late final ProviderSubscription _applicationSub;

  @override
  void dispose() {
    _authSub.close();
    _guestSub.close();
    _roleSub.close();
    _applicationSub.close();
    super.dispose();
  }
}
