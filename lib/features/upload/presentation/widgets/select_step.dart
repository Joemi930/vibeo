import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../providers/upload_providers.dart';
import 'banners.dart';
import 'dashed_border_painter.dart';

/// Étape 1 — choix du fichier (`Maquettes/Upload1.dc.html`).
class SelectStep extends ConsumerWidget {
  const SelectStep({this.errorMessage, super.key});

  final String? errorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supportsCompression = ref
        .watch(videoCompressorProvider)
        .supportsCompression;
    final subtitle =
        'MP4 ou MOV · jusqu\'à ${MediaLimits.formatBytes(MediaLimits.maxVideoBytes)} · '
        '${MediaLimits.maxVideoDuration.inMinutes} min max';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              CustomPaint(
                painter: DashedRoundedBorderPainter(
                  color: theme.colorScheme.outline,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 38,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primaryContainer,
                        ),
                        child: Icon(
                          Icons.video_call_rounded,
                          size: 34,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choisis une vidéo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GradientButton(
                        label: 'Parcourir',
                        onPressed: () => ref
                            .read(uploadControllerProvider.notifier)
                            .pickAndPrepare(),
                      ),
                    ],
                  ),
                ),
              ),
              if (!supportsCompression) ...[
                const SizedBox(height: 16),
                const InfoBanner(
                  text:
                      "La compression n'est pas disponible dans le "
                      'navigateur. Pour les fichiers volumineux, publie '
                      "plutôt depuis l'application Android.",
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: errorMessage!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
