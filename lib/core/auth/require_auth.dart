import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../router/app_routes.dart';
import '../widgets/gradient_button.dart';

/// Action réservée aux membres, pour formuler un message d'invitation adapté.
enum AuthGate {
  like('aimer ce clip'),
  comment('commenter'),
  subscribe("t'abonner à cet artiste"),
  report('signaler ce contenu'),
  playlist('ajouter ce clip à une playlist'),
  library('accéder à ta bibliothèque'),
  upload('publier un clip');

  const AuthGate(this.phrase);

  /// Complète la phrase « Connecte-toi pour … ».
  final String phrase;
}

/// Vérifie qu'un compte est connecté avant une action réservée aux membres.
///
/// Renvoie `true` si l'action peut se poursuivre. Sinon, ouvre une feuille
/// d'invitation à la connexion et renvoie `false` — l'appelant s'arrête là.
///
/// Note : ce garde-fou est un **confort d'interface**. La barrière réelle reste
/// la RLS Postgres, qui refuse de toute façon l'écriture à un visiteur `anon`.
Future<bool> requireAuth(
  BuildContext context,
  WidgetRef ref, {
  required AuthGate gate,
}) async {
  if (ref.read(isAuthenticatedProvider)) return true;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _SignInPromptSheet(gate: gate),
  );
  return false;
}

/// Feuille glissante « Connecte-toi pour … » proposée aux invités.
class _SignInPromptSheet extends StatelessWidget {
  const _SignInPromptSheet({required this.gate});

  final AuthGate gate;

  /// Renvoie vers l'auth en mémorisant l'endroit exact d'où l'on vient, pour y
  /// revenir une fois connecté.
  void _goToAuth(BuildContext context) {
    final returnTo = GoRouterState.of(context).uri.toString();
    Navigator.of(context).pop();
    context.push('${AppRoutes.auth}?returnTo=${Uri.encodeComponent(returnTo)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Icon(
              Icons.lock_outline_rounded,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Connecte-toi pour ${gate.phrase}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La lecture reste libre. Un compte est nécessaire pour interagir '
              'avec les clips et les artistes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            GradientButton(
              label: 'Se connecter',
              onPressed: () => _goToAuth(context),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _goToAuth(context),
              child: const Text('Créer un compte'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Plus tard'),
            ),
          ],
        ),
      ),
    );
  }
}
