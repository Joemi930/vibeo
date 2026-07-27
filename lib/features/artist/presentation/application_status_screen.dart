import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/application_status.dart';
import 'providers/artist_application_providers.dart';
import 'widgets/application_timeline.dart';
import 'widgets/security_notice_card.dart';

/// Écran de suivi de la candidature artiste : en-tête de statut, frise à 3
/// étapes, motif de décision, et action (annuler ou rejoindre le Studio).
class ApplicationStatusScreen extends ConsumerWidget {
  const ApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applicationAsync = ref.watch(myApplicationProvider);

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Ma candidature'),
      body: applicationAsync.when(
        loading: () => const _StatusSkeleton(),
        error: (_, _) => Center(
          child: ErrorState(
            message: 'Impossible de charger ta candidature.',
            onRetry: () => ref.invalidate(myApplicationProvider),
          ),
        ),
        data: (application) {
          if (application == null) {
            return Center(
              child: EmptyState(
                icon: Icons.hourglass_top_rounded,
                title: 'Aucune candidature',
                message: 'Tu n\'as pas encore déposé de candidature artiste.',
                actionLabel: 'Devenir artiste',
                onAction: () => context.go(AppRoutes.becomeArtist),
              ),
            );
          }
          return _StatusBody(applicationId: application.id);
        },
      ),
    );
  }
}

class _StatusBody extends ConsumerWidget {
  const _StatusBody({required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(myApplicationProvider).asData?.value;
    if (application == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final submitState = ref.watch(artistApplicationControllerProvider);
    final status = application.status;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _StatusHero(status: status, createdAt: application.createdAt),
            const SizedBox(height: 26),
            Text(
              'SUIVI',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            ApplicationTimeline(
              status: status,
              createdAt: application.createdAt,
              decidedAt: application.decidedAt,
            ),
            if (application.decisionReason != null &&
                application.decisionReason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _DecisionReasonCard(
                reason: application.decisionReason!,
                isRejected: status.isRejected,
              ),
            ],
            const SizedBox(height: 22),
            const SecurityNoticeCard(
              icon: Icons.info_rounded,
              emphasized: false,
              message:
                  'Ton document d\'identité sera supprimé automatiquement '
                  'dès la décision rendue.',
            ),
            const SizedBox(height: 24),
            if (status.isApproved)
              GradientButton(
                label: 'Aller au Studio',
                onPressed: () => context.go(AppRoutes.studio),
              )
            else if (status.isOpen)
              OutlinedButton(
                onPressed: submitState.isSubmitting
                    ? null
                    : () => _confirmCancel(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
                child: submitState.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Annuler ma candidature'),
              )
            else if (status.isRejected)
              GradientButton(
                label: 'Nouvelle candidature',
                onPressed: () => context.go(AppRoutes.becomeArtist),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler la candidature ?'),
        content: const Text(
          'Cette action est définitive. Tu pourras déposer une nouvelle '
          'candidature plus tard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Annuler la candidature'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ref
        .read(artistApplicationControllerProvider.notifier)
        .cancel(applicationId);
    if (!context.mounted) return;
    if (!ok) {
      final error = ref.read(artistApplicationControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'L\'annulation a échoué.')),
      );
    }
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.status, required this.createdAt});

  final ApplicationStatus status;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final scheme = theme.colorScheme;

    final (IconData icon, String subtitle) = switch (status) {
      ApplicationStatus.pending => (
        Icons.hourglass_top_rounded,
        'Réponse estimée sous 48 h',
      ),
      ApplicationStatus.manualReview => (
        Icons.search_rounded,
        'Examen approfondi en cours',
      ),
      ApplicationStatus.approved => (
        Icons.check_circle_rounded,
        'Bienvenue parmi les artistes vérifiés',
      ),
      ApplicationStatus.rejected => (
        Icons.cancel_rounded,
        'Candidature non retenue',
      ),
    };

    final bool isDecision = status.isApproved || status.isRejected;
    final Color background = isDecision
        ? (status.isApproved ? vibeo.successContainer : scheme.errorContainer)
        : scheme.primaryContainer;
    final Color foreground = isDecision
        ? (status.isApproved
              ? vibeo.onSuccessContainer
              : scheme.onErrorContainer)
        : scheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: isDecision ? null : vibeo.gradient,
              color: isDecision ? foreground.withValues(alpha: 0.15) : null,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isDecision ? foreground : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionReasonCard extends StatelessWidget {
  const _DecisionReasonCard({required this.reason, required this.isRejected});

  final String reason;
  final bool isRejected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: isRejected
              ? scheme.errorContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          reason,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isRejected ? scheme.onErrorContainer : scheme.onSurface,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _StatusSkeleton extends StatelessWidget {
  const _StatusSkeleton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            SizedBox(width: double.infinity, child: SkeletonBox(height: 90)),
            SizedBox(height: 26),
            SizedBox(width: double.infinity, child: SkeletonBox(height: 220)),
          ],
        ),
      ),
    );
  }
}
