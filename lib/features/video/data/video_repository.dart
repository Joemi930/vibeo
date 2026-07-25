import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/media_limits.dart';
import '../domain/genre.dart';
import '../domain/video.dart';
import '../domain/video_status.dart';

/// Contrat d'accès aux clips et aux genres.
///
/// L'abstraction sert de couture de test : les tests injectent un faux
/// repository plutôt que de simuler un client Supabase.
abstract class VideoRepository {
  /// Fil « Nouveautés » : clips publiés, du plus récent au plus ancien.
  Future<List<Video>> fetchPublished({
    int limit = 20,
    int offset = 0,
    int? genreId,
  });

  /// Un clip par son identifiant (null s'il n'existe pas ou n'est pas visible).
  Future<Video?> fetchById(String videoId);

  /// Tous les clips d'un artiste. [onlyPublished] pour la page publique ;
  /// `false` pour le Studio, où l'artiste voit aussi ses brouillons.
  Future<List<Video>> fetchByArtist(
    String artistId, {
    bool onlyPublished = true,
  });

  /// Liste de référence des genres musicaux.
  Future<List<Genre>> fetchGenres();

  /// Téléverse le fichier vidéo et renvoie son chemin de stockage.
  Future<String> uploadVideoFile({
    required String userId,
    required String videoId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
    void Function(double progress)? onProgress,
  });

  /// Téléverse la miniature et renvoie son chemin de stockage.
  Future<String> uploadThumbnail({
    required String userId,
    required String videoId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  });

  /// Crée la ligne du clip. Le serveur refuse si l'appelant n'est pas artiste
  /// ou s'il a dépassé son quota de 5 publications par jour.
  Future<Video> createVideo({
    required String artistId,
    required String title,
    required String videoPath,
    String? description,
    int? genreId,
    String? thumbnailPath,
    int? durationSeconds,
    int? sizeBytes,
    VideoStatus status = VideoStatus.published,
  });

  /// Met à jour les champs éditables d'un clip.
  ///
  /// Seuls les champs fournis sont modifiés. [clearDescription] et
  /// [clearGenre] permettent de vider un champ, ce qu'un `null` ne saurait
  /// exprimer (il signifie « ne touche pas »).
  Future<Video> updateVideo({
    required String videoId,
    String? title,
    String? description,
    int? genreId,
    String? thumbnailPath,
    bool clearDescription = false,
    bool clearGenre = false,
  });

  /// Supprime un fichier de miniature devenu inutile (remplacement).
  Future<void> removeThumbnailFile(String storagePath);

  /// Supprime un clip et ses fichiers.
  Future<void> deleteVideo(Video video);

  /// URL signée temporaire pour lire le fichier vidéo.
  Future<String?> signedVideoUrl(String? storagePath);

  /// URL signée temporaire pour afficher une miniature.
  Future<String?> signedThumbnailUrl(String? storagePath);

  /// Enregistre une vue. Renvoie `true` si elle a été comptabilisée.
  ///
  /// Le serveur applique la règle des 10 secondes et l'anti-spam : appeler
  /// cette méthode plus souvent ne gonfle pas le compteur.
  Future<bool> recordView({
    required String videoId,
    required int watchedSeconds,
    String? sessionKey,
  });
}

/// Implémentation Supabase de [VideoRepository].
class SupabaseVideoRepository implements VideoRepository {
  SupabaseVideoRepository(this._client);

  final SupabaseClient _client;

  static const String _videosTable = 'videos';
  static const String _genresTable = 'genres';
  static const String _videosBucket = 'videos';
  static const String _thumbnailsBucket = 'thumbnails';

  /// Colonnes sélectionnées, avec l'artiste joint pour l'affichage des cartes.
  static const String _selectWithArtist = '''
    *,
    artist:profiles!videos_artist_id_fkey (
      id, username, display_name, avatar_url, role, subscriber_count
    )
  ''';

  @override
  Future<List<Video>> fetchPublished({
    int limit = 20,
    int offset = 0,
    int? genreId,
  }) async {
    var query = _client
        .from(_videosTable)
        .select(_selectWithArtist)
        .eq('status', VideoStatus.published.value);

    if (genreId != null) {
      query = query.eq('genre_id', genreId);
    }

    final rows = await query
        .order('published_at', ascending: false)
        .range(offset, offset + limit - 1);

    return rows.map<Video>(Video.fromJson).toList();
  }

  @override
  Future<Video?> fetchById(String videoId) async {
    final row = await _client
        .from(_videosTable)
        .select(_selectWithArtist)
        .eq('id', videoId)
        .maybeSingle();
    if (row == null) return null;
    return Video.fromJson(row);
  }

  @override
  Future<List<Video>> fetchByArtist(
    String artistId, {
    bool onlyPublished = true,
  }) async {
    var query = _client
        .from(_videosTable)
        .select(_selectWithArtist)
        .eq('artist_id', artistId);

    if (onlyPublished) {
      query = query.eq('status', VideoStatus.published.value);
    }

    final rows = await query.order('created_at', ascending: false);
    return rows.map<Video>(Video.fromJson).toList();
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    final rows = await _client.from(_genresTable).select().order('name');
    return rows.map<Genre>(Genre.fromJson).toList();
  }

  @override
  Future<String> uploadVideoFile({
    required String userId,
    required String videoId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    // Premier segment = auth.uid() : exigé par la RLS du bucket.
    final path = '$userId/$videoId.$fileExtension';
    onProgress?.call(0);
    await _client.storage
        .from(_videosBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    onProgress?.call(1);
    return path;
  }

  @override
  Future<String> uploadThumbnail({
    required String userId,
    required String videoId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    final path = '$userId/$videoId.$fileExtension';
    await _client.storage
        .from(_thumbnailsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  @override
  Future<Video> createVideo({
    required String artistId,
    required String title,
    required String videoPath,
    String? description,
    int? genreId,
    String? thumbnailPath,
    int? durationSeconds,
    int? sizeBytes,
    VideoStatus status = VideoStatus.published,
  }) async {
    final row = await _client
        .from(_videosTable)
        .insert({
          'artist_id': artistId,
          'title': title,
          'description': ?description,
          'genre_id': ?genreId,
          'video_path': videoPath,
          'thumbnail_path': ?thumbnailPath,
          'duration_seconds': ?durationSeconds,
          'size_bytes': ?sizeBytes,
          'status': status.value,
        })
        .select(_selectWithArtist)
        .single();
    return Video.fromJson(row);
  }

  @override
  Future<Video> updateVideo({
    required String videoId,
    String? title,
    String? description,
    int? genreId,
    String? thumbnailPath,
    bool clearDescription = false,
    bool clearGenre = false,
  }) async {
    final row = await _client
        .from(_videosTable)
        .update({
          'title': ?title,
          if (clearDescription)
            'description': null
          else
            'description': ?description,
          if (clearGenre) 'genre_id': null else 'genre_id': ?genreId,
          'thumbnail_path': ?thumbnailPath,
        })
        .eq('id', videoId)
        .select(_selectWithArtist)
        .single();
    return Video.fromJson(row);
  }

  @override
  Future<void> removeThumbnailFile(String storagePath) async {
    if (storagePath.isEmpty) return;
    await _client.storage.from(_thumbnailsBucket).remove([storagePath]);
  }

  @override
  Future<void> deleteVideo(Video video) async {
    // La ligne d'abord : si la RLS refuse, on n'aura pas détruit les fichiers.
    await _client.from(_videosTable).delete().eq('id', video.id);
    await _client.storage.from(_videosBucket).remove([video.videoPath]);
    final thumbnail = video.thumbnailPath;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      await _client.storage.from(_thumbnailsBucket).remove([thumbnail]);
    }
  }

  @override
  Future<String?> signedVideoUrl(String? storagePath) =>
      _signedUrl(_videosBucket, storagePath);

  @override
  Future<String?> signedThumbnailUrl(String? storagePath) =>
      _signedUrl(_thumbnailsBucket, storagePath);

  Future<String?> _signedUrl(String bucket, String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    return _client.storage
        .from(bucket)
        .createSignedUrl(storagePath, MediaLimits.signedUrlTtlSeconds);
  }

  @override
  Future<bool> recordView({
    required String videoId,
    required int watchedSeconds,
    String? sessionKey,
  }) async {
    final result = await _client.rpc(
      'record_view',
      params: {
        'p_video_id': videoId,
        'p_watched_seconds': watchedSeconds,
        'p_session_key': sessionKey,
      },
    );
    return result == true;
  }
}
