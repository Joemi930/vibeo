import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../video/domain/video.dart';
import '../../../video/domain/video_status.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../../data/video_compressor.dart';

/// Étape courante du parcours de publication (voir `Maquettes/Upload1-4`).
enum UploadStep {
  /// 1 — choix du fichier.
  select,

  /// 2 — compression sur l'appareil, avec anneau de progression.
  compressing,

  /// 3 — saisie du titre, de la description et du genre.
  details,

  /// 4 — envoi puis confirmation.
  sending,
  done,
}

@immutable
class UploadState {
  const UploadState({
    this.step = UploadStep.select,
    this.source,
    this.compressed,
    this.progress = 0,
    this.errorMessage,
    this.published,
  });

  final UploadStep step;
  final VideoSource? source;
  final CompressedVideo? compressed;

  /// Progression de l'étape courante, entre 0 et 1.
  final double progress;
  final String? errorMessage;

  /// Clip publié, disponible une fois l'étape [UploadStep.done] atteinte.
  final Video? published;

  bool get isBusy =>
      step == UploadStep.compressing || step == UploadStep.sending;

  UploadState copyWith({
    UploadStep? step,
    VideoSource? source,
    CompressedVideo? compressed,
    double? progress,
    String? errorMessage,
    Video? published,
    bool clearError = false,
  }) {
    return UploadState(
      step: step ?? this.step,
      source: source ?? this.source,
      compressed: compressed ?? this.compressed,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      published: published ?? this.published,
    );
  }
}

/// Fournit le compresseur adapté à la plateforme (surchargeable en test).
final videoCompressorProvider = Provider<VideoCompressor>((ref) {
  return createVideoCompressor();
});

/// Orchestre le parcours de publication : sélection → compression → détails →
/// envoi.
///
/// La compression a lieu **sur l'appareil** avant l'upload : c'est ce qui
/// permet de tenir le budget 0 € (aucun transcodage serveur) et de rester dans
/// le quota de stockage du tier gratuit.
class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadState();

  /// Ouvre le sélecteur de fichiers puis enchaîne sur la compression.
  Future<void> pickAndPrepare() async {
    state = const UploadState();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: MediaLimits.videoExtensions,
        // Sur le web il n'existe pas de chemin de fichier : il faut les octets.
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final source = VideoSource(
        name: file.name,
        sizeBytes: file.size,
        path: file.path,
        bytes: file.bytes,
      );
      state = state.copyWith(source: source, clearError: true);
      await _prepare(source);
    } catch (_) {
      state = state.copyWith(
        step: UploadStep.select,
        errorMessage: 'Impossible d\'ouvrir ce fichier. Réessaie.',
      );
    }
  }

  Future<void> _prepare(VideoSource source) async {
    state = state.copyWith(step: UploadStep.compressing, progress: 0);
    try {
      final compressed = await ref
          .read(videoCompressorProvider)
          .compress(
            source,
            onProgress: (value) => state = state.copyWith(progress: value),
          );
      state = state.copyWith(
        step: UploadStep.details,
        compressed: compressed,
        progress: 1,
        clearError: true,
      );
    } on CompressionException catch (e) {
      // Message déjà rédigé pour l'utilisateur (taille, durée, plateforme).
      state = state.copyWith(step: UploadStep.select, errorMessage: e.message);
    } catch (_) {
      state = state.copyWith(
        step: UploadStep.select,
        errorMessage: 'La préparation du clip a échoué. Réessaie.',
      );
    }
  }

  /// Téléverse le clip et crée sa fiche. Renvoie `true` en cas de succès.
  ///
  /// Le serveur reste seul juge : il refuse si l'appelant n'est pas artiste ou
  /// s'il a dépassé son quota de 5 publications sur 24 h.
  Future<bool> publish({
    required String artistId,
    required String title,
    String? description,
    int? genreId,
  }) async {
    final compressed = state.compressed;
    if (compressed == null) return false;

    state = state.copyWith(
      step: UploadStep.sending,
      progress: 0,
      clearError: true,
    );

    final repo = ref.read(videoRepositoryProvider);
    // Identifiant tiré côté client pour nommer les fichiers avant d'insérer la
    // ligne : le chemin doit commencer par l'uid de l'artiste (RLS storage).
    final videoId = _newId();

    try {
      final videoPath = await repo.uploadVideoFile(
        userId: artistId,
        videoId: videoId,
        bytes: compressed.bytes,
        fileExtension: compressed.fileExtension,
        contentType: compressed.contentType,
        onProgress: (value) => state = state.copyWith(progress: value * 0.9),
      );

      String? thumbnailPath;
      final thumbnail = compressed.thumbnailBytes;
      if (thumbnail != null && thumbnail.isNotEmpty) {
        thumbnailPath = await repo.uploadThumbnail(
          userId: artistId,
          videoId: videoId,
          bytes: thumbnail,
          fileExtension: 'jpg',
          contentType: 'image/jpeg',
        );
      }

      state = state.copyWith(progress: 0.95);

      final video = await repo.createVideo(
        artistId: artistId,
        title: title.trim(),
        videoPath: videoPath,
        description: description?.trim(),
        genreId: genreId,
        thumbnailPath: thumbnailPath,
        durationSeconds: compressed.durationSeconds,
        sizeBytes: compressed.sizeBytes,
        // Pas de modération avant la Phase 4 : publication directe.
        status: VideoStatus.published,
      );

      ref.invalidate(publishedVideosProvider);
      ref.invalidate(studioVideosProvider);

      state = state.copyWith(
        step: UploadStep.done,
        progress: 1,
        published: video,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        step: UploadStep.details,
        errorMessage: _publishError(e),
      );
      return false;
    }
  }

  /// Traduit les refus du serveur en messages compréhensibles.
  static String _publishError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('limite de 5 publications')) {
      return 'Tu as atteint la limite de 5 publications par jour. '
          'Réessaie demain.';
    }
    if (raw.contains('row-level security') || raw.contains('42501')) {
      return 'Seuls les artistes vérifiés peuvent publier un clip.';
    }
    return 'L\'envoi a échoué. Vérifie ta connexion et réessaie.';
  }

  /// Revient à l'étape de sélection en conservant l'écran ouvert.
  void reset() => state = const UploadState();

  /// Annule une compression en cours.
  Future<void> cancel() async {
    await ref.read(videoCompressorProvider).cancel();
    state = const UploadState();
  }

  static String _newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final salt = identityHashCode(Object()).toRadixString(16);
    return '$now$salt';
  }
}

final uploadControllerProvider =
    NotifierProvider<UploadController, UploadState>(UploadController.new);
