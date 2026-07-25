import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/require_auth.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'widgets/history_tab.dart';
import 'widgets/playlists_tab.dart';
import 'widgets/subscriptions_tab.dart';

/// Bibliothèque : playlists, abonnements et historique de lecture.
///
/// Réservée aux membres (voir `Maquettes/Library.dc.html`) : un invité qui
/// atteindrait cet onglet — la garde du router le bloque déjà normalement —
/// se voit proposer l'écran de connexion plutôt qu'un contenu vide.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(isAuthenticatedProvider)) {
        requireAuth(context, ref, gate: AuthGate.library);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);

    if (!isAuthenticated) {
      return Scaffold(
        appBar: const VibeoAppBar(title: 'Bibliothèque'),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Bibliothèque réservée aux membres',
          message:
              'Retrouve tes playlists, tes abonnements et ton historique de '
              'lecture une fois connecté.',
          actionLabel: 'Voir comment me connecter',
          onAction: () => requireAuth(context, ref, gate: AuthGate.library),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const VibeoAppBar(
          title: 'Bibliothèque',
          bottom: TabBar(
            tabs: [
              Tab(text: 'Playlists'),
              Tab(text: 'Abonnements'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [PlaylistsTab(), SubscriptionsTab(), HistoryTab()],
        ),
      ),
    );
  }
}
