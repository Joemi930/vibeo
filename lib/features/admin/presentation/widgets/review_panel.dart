import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/admin_application.dart';
import '../providers/admin_providers.dart';
import 'confirm_action_dialog.dart';
import 'secure_document_viewer.dart';

/// Panneau d'examen d'une candidature artiste (384 px en desktop, plein
/// écran en mobile).
///
/// Affiche les informations du candidat, le document d'identité via
/// [SecureDocumentViewer], et les boutons Approuver / Rejeter.
///
/// Le rejet exige un motif saisi dans [showConfirmActionDialog].
class ReviewPanel extends ConsumerWidget {
  const ReviewPanel({
    required this.application,
    required this.onClose,
    super.key,
  });

  final AdminApplication application;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final isActing = ref.watch(adminActionControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        // En desktop (conteneur large > 500px), largeur fixe 384 px.
        // En mobile, prend toute la largeur disponible.
        final isWide = constraints.maxWidth > 500;
        return Container(
          width: isWide ? 384 : null,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              left: isWide
                  ? BorderSide(color: theme.colorScheme.outlineVariant)
                  : BorderSide.none,
            ),
          ),
          child: Column(
            children: [
              // En-tête
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Examen — ${application.resolvedName}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Fermer',
                    ),
                  ],
                ),
              ),

              // Contenu défilable
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  children: [
                    // Informations candidat
                    _buildSectionTitle(context, 'Candidat'),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      context,
                      'Nom de scène',
                      application.stageName.isNotEmpty
                          ? application.stageName
                          : application.resolvedName,
                    ),
                    if (application.displayName != null &&
                        application.displayName!.isNotEmpty)
                      _buildInfoRow(
                        context,
                        'Nom du profil',
                        application.displayName!,
                      ),
                    _buildInfoRow(
                      context,
                      'Identifiant',
                      '@${application.username}',
                    ),
                    if (application.links.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildSectionTitle(context, 'Liens'),
                      const SizedBox(height: 6),
                      for (final link in application.links)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            link,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 11.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    if (application.statement.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildSectionTitle(context, 'Présentation'),
                      const SizedBox(height: 6),
                      Text(
                        application.statement,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Document d'identité
                    if (application.hasDocument)
                      SecureDocumentViewer(applicationId: application.id),

                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Barre d'actions
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: isActing
                            ? null
                            : () => _approve(context, ref),
                        style: FilledButton.styleFrom(
                          backgroundColor: vibeo.success,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Approuver'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: isActing
                            ? null
                            : () => _reject(context, ref),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Text('Rejeter'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.04,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approuver cette candidature ?'),
        content: const Text(
          'L\'artiste recevra le statut « vérifié » et pourra publier ses '
          'clips immédiatement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approuver'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .decideApplication(
          applicationId: application.id,
          approve: true,
          reason: 'Approuvé',
        );
    if (error != null && context.mounted) {
      _showError(context, error);
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final result = await showConfirmActionDialog(
      context: context,
      title: 'Rejeter cette candidature ?',
      message:
          'Cette action est irréversible. L\'utilisateur pourra présenter une '
          'nouvelle candidature après 7 jours.',
      confirmLabel: 'Rejeter',
      isDestructive: true,
      requireReason: true,
      reasonLabel: 'Motif du rejet',
      reasonHint: 'Explique pourquoi cette candidature est refusée…',
    );
    if (!result.confirmed || !context.mounted) return;

    final error = await ref
        .read(adminActionControllerProvider.notifier)
        .decideApplication(
          applicationId: application.id,
          approve: false,
          reason: result.reason,
        );
    if (error != null && context.mounted) {
      _showError(context, error);
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
