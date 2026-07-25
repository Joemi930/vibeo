import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/vibeo_app_bar.dart';
import '../../upload/presentation/widgets/banners.dart';
import '../../upload/presentation/widgets/thumbnail_field.dart';
import '../../video/domain/video.dart';
import '../../video/presentation/providers/video_providers.dart';
import 'providers/studio_providers.dart';

/// Modification d'un clip déjà publié, depuis le Studio.
///
/// Le fichier vidéo n'est pas remplaçable ici : seuls la fiche (titre,
/// description, genre) et la miniature évoluent. La RLS vérifie de toute façon
/// que l'appelant est bien l'artiste propriétaire.
class EditVideoScreen extends ConsumerWidget {
  const EditVideoScreen({required this.videoId, super.key});

  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videoAsync = ref.watch(videoByIdProvider(videoId));

    return Scaffold(
      appBar: const VibeoAppBar(title: 'Modifier le clip'),
      body: videoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: ErrorState(
            message: 'Impossible de charger ce clip.',
            onRetry: () => ref.invalidate(videoByIdProvider(videoId)),
          ),
        ),
        data: (video) => video == null
            ? const Center(
                child: EmptyState(
                  icon: Icons.videocam_off_outlined,
                  title: 'Ce clip est introuvable',
                  message: 'Il a peut-être été supprimé.',
                ),
              )
            : _EditForm(video: video),
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.video});

  final Video video;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late int? _genreId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.video.title);
    _descriptionController = TextEditingController(
      text: widget.video.description ?? '',
    );
    _genreId = widget.video.genreId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    final description = _descriptionController.text.trim();
    final saved = await ref
        .read(editVideoControllerProvider.notifier)
        .save(
          video: widget.video,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          genreId: _genreId,
        );

    if (!mounted || !saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Clip mis à jour.')));
    VibeoAppBar.popOrGo(context, '/studio');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edit = ref.watch(editVideoControllerProvider);
    final controller = ref.read(editVideoControllerProvider.notifier);
    final genresAsync = ref.watch(genresProvider);
    final currentThumbnailUrl = ref
        .watch(thumbnailUrlProvider(widget.video.thumbnailPath))
        .asData
        ?.value;

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
                      ThumbnailField(
                        bytes: edit.thumbnail?.bytes,
                        imageUrl: currentThumbnailUrl,
                        enabled: !edit.isSaving,
                        onChoose: controller.chooseThumbnail,
                        onReset: edit.thumbnail != null
                            ? controller.keepCurrentThumbnail
                            : null,
                        resetLabel: 'Miniature actuelle',
                      ),
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
                            return ChoiceChip(
                              label: Text(genre.name),
                              selected: _genreId == genre.id,
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
                      if (edit.errorMessage != null) ...[
                        const SizedBox(height: 18),
                        ErrorBanner(message: edit.errorMessage!),
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
                  label: 'Enregistrer',
                  loading: edit.isSaving,
                  onPressed: edit.isSaving ? null : _save,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
