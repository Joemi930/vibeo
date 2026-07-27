import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/dev_log.dart';

import '../../../video/domain/video.dart';
import '../../../video/domain/video_status.dart';
import '../../../video/presentation/providers/video_providers.dart';
import '../../data/thumbnail_picker.dart';
import '../../data/video_compressor.dart';
import '../../data/video_picker.dart';

/// Étape courante du parcours de publication (voir `Maquettes/Upload1-4`).
enum UploadStep {
  /// 1 — choix du fichier.
  select,

  /// 2 — compression sur l'appareil, avec anneau de progression.
  compressing,

  /// 3 — miniature, titre, description et genre.
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
    this.thumbnail,
    this.progress = 0,
    this.errorMessage,
    this.published,
    this.moderationRequested = true,
  });

  final UploadStep step;
  final VideoSource? source;
  final CompressedVideo? compressed;

  /// Miniature choisie par l'artiste, qui remplace celle extraite du clip.
  final PickedThumbnail? thumbnail;

  /// Progression de l'étape courante, entre 0 et 1.
  final double progress;
  final String? errorMessage;

  /// Clip envoyé, disponible une fois l'étape [UploadStep.done] atteinte.
  final Video? published;

  /// La vérification automatique a bien été demandée.
  ///
  /// À faux, le clip est en ligne mais personne ne l'a encore examiné : l'écran
  /// de confirmation propose alors de relancer. Sans ce drapeau, un artiste
  /// verrait « Envoi terminé » puis un clip qui ne sort jamais de l'attente,
  /// sans comprendre pourquoi.
  final bool moderationRequested;

  bool get isBusy =>
      step == UploadStep.compressing || step == UploadStep.sending;

  /// Miniature réellement envoyée : celle choisie, sinon celle extraite du clip.
  Uint8List? get thumbnailBytes =>
      thumbnail?.bytes ?? compressed?.thumbnailBytes;

  /// Vrai si la miniature affichée a été choisie à la main.
  bool get hasCustomThumbnail => thumbnail != null;

  String get thumbnailExtension => thumbnail?.fileExtension ?? 'jpg';
  String get thumbnailContentType => thumbnail?.contentType ?? 'image/jpeg';

  UploadState copyWith({
    UploadStep? step,
    VideoSource? source,
    CompressedVideo? compressed,
    PickedThumbnail? thumbnail,
    double? progress,
    String? errorMessage,
    Video? published,
    bool? moderationRequested,
    bool clearError = false,
    bool clearThumbnail = false,
  }) {
    return UploadState(
      step: step ?? this.step,
      source: source ?? this.source,
      compressed: compressed ?? this.compressed,
      thumbnail: clearThumbnail ? null : (thumbnail ?? this.thumbnail),
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      published: published ?? this.published,
      moderationRequested: moderationRequested ?? this.moderationRequested,
    );
  }
}

/// Fournit le compresseur adapté à la plateforme (surchargeable en test).
final videoCompressorProvider = Provider<VideoCompressor>((ref) {
  return createVideoCompressor();
});

/// Fournit le sélecteur de fichiers adapté à la plateforme.
final videoPickerProvider = Provider<VideoPicker>((ref) {
  return createVideoPicker();
});

/// Vrai si l'appareil sait compresser un clip.
///
/// Toujours vrai sur Android ; sur le web, dépend de la présence d'un encodeur
/// H.264 exploitable par WebCodecs — c'est le cas de Chrome, Edge et Safari,
/// pas de Firefox à ce jour. Sert à avertir l'artiste **avant** qu'il choisisse
/// un fichier trop lourd.
final compressionSupportProvider = FutureProvider<bool>((ref) {
  return ref.watch(videoCompressorProvider).supportsCompression;
});

/// Orchestre le parcours de publication : sélection → compression → détails →
/// envoi.
///
/// La compression a lieu **chez l'utilisateur** avant l'upload — encodeurs
/// natifs sur Android, WebCodecs dans le navigateur. C'est ce qui permet de
/// tenir le budget 0 € (aucun transcodage serveur) et de rester dans le quota
/// de stockage du tier gratuit.
class UploadController extends Notifier<UploadState> {
  @override
  UploadState build() => const UploadState();

  /// Ouvre le sélecteur de fichiers puis enchaîne sur la compression.
  Future<void> pickAndPrepare() async {
    state = const UploadState();
    final VideoSource? source;
    try {
      source = await ref.read(videoPickerProvider).pickVideo();
    } on PickerException catch (e) {
      state = state.copyWith(step: UploadStep.select, errorMessage: e.message);
      return;
    } catch (error, stack) {
      // Ce `catch` était muet : la sélection échouait sans qu'aucune trace ne
      // permette de savoir pourquoi. Le détail technique reste visible en
      // développement, l'utilisateur ne voit qu'un message clair.
      logError('sélection de fichier impossible', error, stack);
      state = state.copyWith(
        step: UploadStep.select,
        errorMessage: _withDebugDetail(
          'Impossible d\'ouvrir ce fichier. Réessaie.',
          error,
        ),
      );
      return;
    }

    if (source == null) return;
    state = state.copyWith(source: source, clearError: true);
    await _prepare(source);
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
    } catch (error, stack) {
      logError('préparation du clip impossible', error, stack);
      state = state.copyWith(
        step: UploadStep.select,
        errorMessage: _withDebugDetail(
          'La préparation du clip a échoué. Réessaie.',
          error,
        ),
      );
    }
  }

  /// Remplace la miniature extraite du clip par une image choisie.
  Future<void> chooseThumbnail() async {
    try {
      final picked = await pickThumbnailImage();
      if (picked == null) return;
      state = state.copyWith(thumbnail: picked, clearError: true);
    } on PickerException catch (e) {
      state = state.copyWith(errorMessage: e.message);
    } catch (error, stack) {
      logError('choix de miniature impossible', error, stack);
      state = state.copyWith(
        errorMessage: _withDebugDetail(
          'Impossible d\'ouvrir cette image. Réessaie.',
          error,
        ),
      );
    }
  }

  /// Revient à la miniature extraite automatiquement du clip.
  void useAutomaticThumbnail() =>
      state = state.copyWith(clearThumbnail: true, clearError: true);

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
      final thumbnail = state.thumbnailBytes;
      if (thumbnail != null && thumbnail.isNotEmpty) {
        thumbnailPath = await repo.uploadThumbnail(
          userId: artistId,
          videoId: videoId,
          bytes: thumbnail,
          fileExtension: state.thumbnailExtension,
          contentType: state.thumbnailContentType,
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
        // Depuis la Phase 4, c'est le SEUL statut que la base accepte à la
        // création : le trigger `videos_guard_client_fields` refuse tout le
        // reste. Un clip naît invisible et ne devient public que par la
        // modération, ci-dessous.
        status: VideoStatus.processing,
      );

      // La vérification est demandée tout de suite. Son échec n'est pas
      // fatal : le clip reste en attente et sera repris, soit par le bouton
      // « Relancer la vérification » du Studio, soit par la reprise planifiée.
      // Bloquer l'envoi ici ferait croire à l'artiste que sa publication a
      // échoué alors que son fichier est bien arrivé.
      final moderationRequested = await _requestModeration(video.id);

      ref.invalidate(publishedVideosProvider);
      ref.invalidate(studioVideosProvider);

      state = state.copyWith(
        step: UploadStep.done,
        progress: 1,
        published: video,
        moderationRequested: moderationRequested,
      );
      return true;
    } catch (error, stack) {
      logError('publication impossible', error, stack);
      state = state.copyWith(
        step: UploadStep.details,
        errorMessage: _publishError(error),
      );
      return false;
    }
  }

  /// Demande la vérification automatique d'un clip fraîchement envoyé.
  ///
  /// Renvoie `false` si l'appel n'a pas abouti — l'écran de confirmation
  /// propose alors de relancer. Ne lève jamais : à ce stade le fichier est
  /// déjà en ligne et la ligne créée, il serait faux de présenter l'envoi
  /// comme échoué.
  Future<bool> _requestModeration(String videoId) async {
    try {
      final response = await ref
          .read(supabaseClientProvider)
          .functions
          .invoke('moderate-video', body: {'videoId': videoId});
      // Le SDK `supabase_flutter` ne lève PAS d'exception sur les 4xx/5xx :
      // il retourne un `FunctionsResponse` avec `.status` et `.data`. Sans
      // cette vérification, un 404 (fonction non déployée) ou un 500 (clé IA
      // absente) étaient avalés silencieusement et le clip restait bloqué en
      // `processing` sans que rien ni personne ne le signale.
      if (response.status != 200) {
        logError('moderate-video a répondu ${response.status}', response.data);
        return false;
      }
      return true;
    } catch (error) {
      logError('demande de vérification impossible', error);
      return false;
    }
  }

  /// Relance la vérification d'un clip resté en attente.
  Future<bool> retryModeration(String videoId) async {
    final ok = await _requestModeration(videoId);
    if (ok) {
      ref.invalidate(studioVideosProvider);
      state = state.copyWith(moderationRequested: true);
    }
    return ok;
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
    return _withDebugDetail(
      'L\'envoi a échoué. Vérifie ta connexion et réessaie.',
      error,
    );
  }

  /// Ajoute la cause technique au message en développement uniquement.
  static String _withDebugDetail(String message, Object error) {
    if (!kDebugMode) return message;
    return '$message\n\n[debug] $error';
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
