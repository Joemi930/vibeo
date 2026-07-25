import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import 'providers/upload_providers.dart';
import 'widgets/compressing_step.dart';
import 'widgets/details_step.dart';
import 'widgets/done_step.dart';
import 'widgets/select_step.dart';
import 'widgets/step_progress_header.dart';

/// Parcours de publication d'un clip en 4 étapes (voir `Maquettes/Upload1-4`).
///
/// N'orchestre que l'affichage : toute la logique (compression, upload,
/// création de la fiche) vit dans [uploadControllerProvider].
class UploadFlowScreen extends ConsumerWidget {
  const UploadFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(uploadControllerProvider);

    return Scaffold(
      appBar: const VibeoAppBar(
        title: 'Nouveau clip',
        fallbackRoute: AppRoutes.studio,
      ),
      body: SafeArea(
        child: Column(
          children: [
            StepProgressHeader(
              stepIndex: _stepIndex(state.step),
              stepLabel: _stepLabel(state.step),
            ),
            const SizedBox(height: 6),
            Expanded(child: _StepBody(state: state)),
          ],
        ),
      ),
    );
  }

  static int _stepIndex(UploadStep step) => switch (step) {
    UploadStep.select => 0,
    UploadStep.compressing => 1,
    UploadStep.details => 2,
    UploadStep.sending || UploadStep.done => 3,
  };

  static String _stepLabel(UploadStep step) => switch (step) {
    UploadStep.select => 'Sélection',
    UploadStep.compressing => 'Compression',
    UploadStep.details => 'Détails',
    UploadStep.sending || UploadStep.done => 'Envoi',
  };
}

class _StepBody extends ConsumerWidget {
  const _StepBody({required this.state});

  final UploadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (state.step) {
      case UploadStep.select:
        return SelectStep(errorMessage: state.errorMessage);
      case UploadStep.compressing:
        return CompressingStep(
          source: state.source,
          compressed: state.compressed,
          progress: state.progress,
        );
      case UploadStep.details:
        return DetailsStep(
          compressed: state.compressed,
          errorMessage: state.errorMessage,
        );
      case UploadStep.sending:
        return const _SendingStep();
      case UploadStep.done:
        final published = state.published;
        return published == null
            ? const SelectStep()
            : DoneStep(published: published);
    }
  }
}

class _SendingStep extends ConsumerWidget {
  const _SendingStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(
      uploadControllerProvider.select((s) => s.progress),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Envoi en cours…',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
