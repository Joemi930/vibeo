import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/admin_application.dart';
import '../providers/admin_providers.dart';
import 'confirm_action_dialog.dart';
import 'score_bar.dart';
import 'secure_document_viewer.dart';

/// Panneau d'examen d'une candidature artiste (volet droit de 384 px).
///
/// Affiche les informations du candidat, le rapport IA (checks convertis en
/// libellés français), le document d'identité via [SecureDocumentViewer], et
/// les boutons Approuver / Rejeter.
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

    return Container(
      width: 384,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
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

                // Score IA
                if (application.aiScore != null) ...[
                  _buildAIScoreCard(context, vibeo),
                  const SizedBox(height: 16),
                ],

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
                    onPressed: isActing ? null : () => _approve(context, ref),
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
                    onPressed: isActing ? null : () => _reject(context, ref),
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

  Widget _buildAIScoreCard(BuildContext context, VibeoColors vibeo) {
    final theme = Theme.of(context);
    final checks = application.aiChecks;
    final score = application.aiScore ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête : icône IA + score global
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: vibeo.info),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Rapport IA',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${score.round()}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: score >= 80
                      ? vibeo.success
                      : score >= 40
                      ? vibeo.warning
                      : theme.colorScheme.error,
                ),
              ),
              Text(
                '/100',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Barre de score
          ScoreBar(score: score, showLabel: false),
          const SizedBox(height: 12),

          // Checks individuels
          if (checks.isNotEmpty)
            for (final check in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      check.passed
                          ? Icons.check_circle_rounded
                          : Icons.warning_rounded,
                      size: 16,
                      color: check.passed ? vibeo.success : vibeo.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        check.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

          // Résumé IA (si présent)
          if (application.aiSummary != null) ...[
            const SizedBox(height: 8),
            Text(
              application.aiSummary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
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
