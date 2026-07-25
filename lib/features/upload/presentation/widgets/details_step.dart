import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/gradient_button.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../../data/video_compressor.dart';
import '../providers/upload_providers.dart';
import 'banners.dart';
import 'thumbnail_field.dart';

/// Étape 3 — titre, description et genre (`Maquettes/Upload3.dc.html`).
class DetailsStep extends ConsumerStatefulWidget {
  const DetailsStep({required this.compressed, this.errorMessage, super.key});

  final CompressedVideo? compressed;
  final String? errorMessage;

  @override
  ConsumerState<DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<DetailsStep> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _genreId;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    final profile = await ref.read(currentProfileProvider.future);
    if (!mounted) return;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil introuvable. Réessaie dans un instant.'),
        ),
      );
      return;
    }

    final description = _descriptionController.text.trim();
    await ref
        .read(uploadControllerProvider.notifier)
        .publish(
          artistId: profile.id,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          genreId: _genreId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final genresAsync = ref.watch(genresProvider);
    final isBusy = ref.watch(uploadControllerProvider.select((s) => s.isBusy));

    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ThumbnailPicker(),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _titleController,
                        maxLength: 120,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Titre'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Le titre est obligatoire.'
                            : null,
                      ),
                      TextFormField(
                        controller: _descriptionController,
                        maxLength: 5000,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Genre',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      genresAsync.when(
                        data: (genres) => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: genres.map((genre) {
                            final selected = _genreId == genre.id;
                            return ChoiceChip(
                              label: Text(genre.name),
                              selected: selected,
                              onSelected: (value) => setState(
                                () => _genreId = value ? genre.id : null,
                              ),
                            );
                          }).toList(),
                        ),
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (_, _) => Text(
                          'Genres indisponibles pour le moment.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (widget.errorMessage != null) ...[
                        const SizedBox(height: 18),
                        ErrorBanner(message: widget.errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: GradientButton(
                  label: 'Publier',
                  loading: isBusy,
                  onPressed: widget.compressed == null ? null : _publish,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Aperçu de la miniature du parcours de publication.
///
/// Par défaut, l'image est extraite du clip à 10 % de sa durée (les premières
/// images sont souvent noires). L'artiste peut la remplacer par un fichier à
/// lui, et revenir à l'image automatique.
class ThumbnailPicker extends ConsumerWidget {
  const ThumbnailPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(uploadControllerProvider);
    final controller = ref.read(uploadControllerProvider.notifier);

    return ThumbnailField(
      bytes: upload.thumbnailBytes,
      enabled: !upload.isBusy,
      onChoose: controller.chooseThumbnail,
      onReset: upload.hasCustomThumbnail
          ? controller.useAutomaticThumbnail
          : null,
    );
  }
}
