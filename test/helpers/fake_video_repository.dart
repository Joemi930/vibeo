import 'dart:typed_data';

import 'package:vibeo/features/video/data/video_repository.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';
import 'package:vibeo/features/video/domain/genre.dart';
import 'package:vibeo/features/video/domain/video.dart';
import 'package:vibeo/features/video/domain/video_status.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';

/// Faux dépôt vidéo, écrit à la main (convention du projet : ni mockito, ni
/// génération de code). Journalise les appels et permet d'injecter des erreurs.
class FakeVideoRepository implements VideoRepository {
  FakeVideoRepository({
    this.videos = const <Video>[],
    this.genres = const <Genre>[],
    this.throwOnFetch = false,
    this.recordViewResult = true,
  });

  List<Video> videos;
  List<Genre> genres;
  bool throwOnFetch;
  bool recordViewResult;

  /// Trace des appels, pour les assertions (ex. `recordView:abc:12`).
  final List<String> calls = [];

  @override
  Future<List<Video>> fetchPublished({
    int limit = 20,
    int offset = 0,
    int? genreId,
  }) async {
    calls.add('fetchPublished:$genreId');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    if (genreId == null) return videos;
    return videos.where((v) => v.genreId == genreId).toList();
  }

  @override
  Future<Video?> fetchById(String videoId) async {
    calls.add('fetchById:$videoId');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    for (final video in videos) {
      if (video.id == videoId) return video;
    }
    return null;
  }

  @override
  Future<List<Video>> fetchByArtist(
    String artistId, {
    bool onlyPublished = true,
  }) async {
    calls.add('fetchByArtist:$artistId:$onlyPublished');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return videos.where((v) => v.artistId == artistId).toList();
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    calls.add('fetchGenres');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return genres;
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
    calls.add('uploadVideoFile:$userId:$videoId');
    onProgress?.call(1);
    return '$userId/$videoId.$fileExtension';
  }

  @override
  Future<String> uploadThumbnail({
    required String userId,
    required String videoId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    calls.add('uploadThumbnail:$userId:$videoId');
    return '$userId/$videoId.$fileExtension';
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
    calls.add('createVideo:$artistId:$title');
    final video = Video(
      id: 'video-${videos.length + 1}',
      artistId: artistId,
      title: title,
      description: description,
      genreId: genreId,
      videoPath: videoPath,
      thumbnailPath: thumbnailPath,
      durationSeconds: durationSeconds,
      sizeBytes: sizeBytes,
      status: status,
      publishedAt: DateTime(2026, 7, 25),
      createdAt: DateTime(2026, 7, 25),
    );
    videos = [...videos, video];
    return video;
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
    calls.add('updateVideo:$videoId');
    final index = videos.indexWhere((v) => v.id == videoId);
    final updated = videos[index].copyWith(
      title: title,
      description: clearDescription ? null : description,
      genreId: clearGenre ? null : genreId,
      thumbnailPath: thumbnailPath,
      clearDescription: clearDescription,
      clearGenre: clearGenre,
    );
    videos = [...videos]..[index] = updated;
    return updated;
  }

  @override
  Future<void> removeThumbnailFile(String storagePath) async {
    calls.add('removeThumbnailFile:$storagePath');
  }

  @override
  Future<void> deleteVideo(Video video) async {
    calls.add('deleteVideo:${video.id}');
    videos = videos.where((v) => v.id != video.id).toList();
  }

  @override
  Future<String?> signedVideoUrl(String? storagePath) async {
    calls.add('signedVideoUrl:$storagePath');
    return storagePath == null ? null : 'https://exemple.test/$storagePath';
  }

  @override
  Future<String?> signedThumbnailUrl(String? storagePath) async {
    // Renvoie null : les tests widget ne doivent jamais tenter un accès réseau
    // pour une image (le visuel de remplacement rayé s'affiche à la place).
    calls.add('signedThumbnailUrl:$storagePath');
    return null;
  }

  @override
  Future<bool> recordView({
    required String videoId,
    required int watchedSeconds,
    String? sessionKey,
  }) async {
    calls.add('recordView:$videoId:$watchedSeconds');
    return recordViewResult;
  }
}

/// Construit un clip de test, avec des valeurs par défaut réalistes.
Video buildTestVideo({
  String id = 'video-1',
  String artistId = 'artist-1',
  String title = 'Mon premier clip',
  String? description,
  int? genreId,
  VideoStatus status = VideoStatus.published,
  int viewCount = 1234,
  int likeCount = 42,
  int? durationSeconds = 214,
  ArtistSummary? artist,
}) {
  return Video(
    id: id,
    artistId: artistId,
    title: title,
    description: description,
    genreId: genreId,
    videoPath: '$artistId/$id.mp4',
    thumbnailPath: '$artistId/$id.jpg',
    durationSeconds: durationSeconds,
    sizeBytes: 5 * 1024 * 1024,
    status: status,
    viewCount: viewCount,
    likeCount: likeCount,
    publishedAt: DateTime(2026, 7, 20),
    createdAt: DateTime(2026, 7, 20),
    artist:
        artist ??
        const ArtistSummary(
          id: 'artist-1',
          username: 'naika',
          displayName: 'Naïka',
          role: UserRole.artist,
          subscriberCount: 412000,
        ),
  );
}
