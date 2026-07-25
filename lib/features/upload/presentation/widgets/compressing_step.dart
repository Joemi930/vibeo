import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/video_compressor.dart';
import '../providers/upload_providers.dart';

/// Étape 2 — compression sur l'appareil (`Maquettes/Upload2.dc.html`).
class CompressingStep extends ConsumerWidget {
  const CompressingStep({
    required this.source,
    required this.compressed,
    required this.progress,
    super.key,
  });

  final VideoSource? source;
  final CompressedVideo? compressed;
  final double progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clamped = progress.clamp(0.0, 1.0);
    final percent = (clamped * 100).round();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CircularProgressIndicator(
                        value: clamped,
                        strokeWidth: 12,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percent%',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 40,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Compression…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Optimisation en cours',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'On réduit le poids sans perte visible. '
                'Ça prend quelques secondes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              _SizeCard(source: source, compressed: compressed),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () =>
                    ref.read(uploadControllerProvider.notifier).cancel(),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeCard extends StatelessWidget {
  const _SizeCard({required this.source, required this.compressed});

  final VideoSource? source;
  final CompressedVideo? compressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vibeo = VibeoColors.of(context);
    final before = source == null
        ? '—'
        : MediaLimits.formatBytes(source!.sizeBytes);
    final after = compressed == null
        ? '…'
        : MediaLimits.formatBytes(compressed!.sizeBytes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SizeColumn(
              label: 'Avant',
              value: before,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Icon(Icons.arrow_forward_rounded, color: theme.colorScheme.tertiary),
          Expanded(
            child: _SizeColumn(
              label: 'Après (est.)',
              value: after,
              color: vibeo.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeColumn extends StatelessWidget {
  const _SizeColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
