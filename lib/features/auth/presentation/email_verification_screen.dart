import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/vibeo_app_bar.dart';

/// Écran affiché après une inscription nécessitant une confirmation par email.
class EmailVerificationScreen extends ConsumerWidget {
  const EmailVerificationScreen({this.email, super.key});

  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const VibeoAppBar(fallbackRoute: AppRoutes.auth),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Vérifie ta boîte mail',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  email == null
                      ? 'Nous t\'avons envoyé un lien de confirmation. '
                            'Clique dessus pour activer ton compte.'
                      : 'Nous avons envoyé un lien de confirmation à $email. '
                            'Clique dessus pour activer ton compte.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.auth),
                  child: const Text('Revenir à la connexion'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
