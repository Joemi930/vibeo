import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/application_status.dart';

const List<String> _frenchMonths = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Formate une date en français sans dépendance à `intl` (absente du
/// pubspec) : « 21 juil. 2026 · 14:32 ».
String _formatFrenchDateTime(DateTime date) {
  final local = date.toLocal();
  final month = _frenchMonths[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month ${local.year} · $hour:$minute';
}

/// Frise verticale à 3 étapes du suivi de candidature (envoyée / en cours
/// d'analyse / décision), calquée sur `ApplicationStatus.dc.html`.
class ApplicationTimeline extends StatelessWidget {
  const ApplicationTimeline({
    required this.status,
    required this.createdAt,
    required this.decidedAt,
    super.key,
  });

  final ApplicationStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;

  @override
  Widget build(BuildContext context) {
    final decisionMade = status.isApproved || status.isRejected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimelineStep(
          state: _StepState.done,
          icon: Icons.check_rounded,
          title: 'Candidature envoyée',
          subtitle: _formatFrenchDateTime(createdAt),
          isLast: false,
        ),
        _TimelineStep(
          state: decisionMade ? _StepState.done : _StepState.active,
          icon: Icons.search_rounded,
          title: 'Analyse par l\'équipe',
          subtitle: decisionMade
              ? 'Terminée'
              : 'En cours — vérification du document et des liens',
          isLast: false,
        ),
        _TimelineStep(
          state: decisionMade ? _StepState.done : _StepState.pending,
          icon: status.isRejected ? Icons.close_rounded : Icons.flag_rounded,
          title: 'Décision',
          subtitle: decisionMade
              ? (decidedAt != null
                    ? _formatFrenchDateTime(decidedAt!)
                    : 'Rendue')
              : 'Tu recevras une notification',
          isLast: true,
          isError: status.isRejected,
        ),
      ],
    );
  }
}

enum _StepState { done, active, pending }

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.state,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLast,
    this.isError = false,
  });

  final _StepState state;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final scheme = theme.colorScheme;

    final Color dotColor = switch (state) {
      _StepState.done when isError => scheme.error,
      _StepState.done => vibeo.success,
      _StepState.active => scheme.primary,
      _StepState.pending => scheme.surfaceContainerHigh,
    };
    final Color iconColor = switch (state) {
      _StepState.pending => scheme.onSurfaceVariant,
      _ => Colors.white,
    };
    final Color lineColor = state == _StepState.pending
        ? scheme.outlineVariant
        : (isError ? scheme.error : vibeo.success);
    final Color titleColor = state == _StepState.pending
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    final Color subtitleColor = state == _StepState.active
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return Semantics(
      label: '$title. $subtitle',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: state == _StepState.pending
                        ? Border.all(color: scheme.outlineVariant, width: 2)
                        : null,
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      constraints: const BoxConstraints(minHeight: 34),
                      color: lineColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
