import 'dart:typed_data';

import 'package:vibeo/features/library/data/playlist_repository.dart';
import 'package:vibeo/features/library/domain/playlist.dart';
import 'package:vibeo/features/video/domain/video.dart';

/// Faux dépôt de playlists, écrit à la main (convention du projet : ni
/// mockito, ni génération de code). Journalise les appels et permet
/// d'injecter des erreurs, sur le modèle de `FakeVideoRepository`.
class FakePlaylistRepository implements PlaylistRepository {
  FakePlaylistRepository({
    List<Playlist> playlists = const [],
    Map<String, List<Video>> items = const {},
    List<Video> history = const [],
    this.throwOnFetch = false,
    this.throwOnWrite = false,
    this.throwOnCoverUpload = false,
  }) : playlists = [...playlists],
       items = {
         for (final e in items.entries) e.key: [...e.value],
       },
       history = [...history];

  List<Playlist> playlists;
  Map<String, List<Video>> items;
  List<Video> history;
  bool throwOnFetch;
  bool throwOnWrite;

  /// Échec isolé du téléversement de couverture, sans affecter les autres
  /// écritures : permet de tester le cas « playlist créée, image en échec ».
  bool throwOnCoverUpload;

  /// Trace des appels, pour les assertions.
  final List<String> calls = [];

  @override
  Future<List<Playlist>> fetchMine() async {
    calls.add('fetchMine');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return playlists;
  }

  @override
  Future<Playlist?> fetchById(String playlistId) async {
    calls.add('fetchById:$playlistId');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    for (final playlist in playlists) {
      if (playlist.id == playlistId) return playlist;
    }
    return null;
  }

  @override
  Future<List<Video>> fetchItems(String playlistId) async {
    calls.add('fetchItems:$playlistId');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return items[playlistId] ?? const [];
  }

  @override
  Future<Playlist> create({
    required String title,
    String? description,
    bool isPublic = false,
  }) async {
    calls.add('create:$title');
    if (throwOnWrite) throw const PlaylistException('Échec simulé.');
    final playlist = Playlist(
      id: 'playlist-${playlists.length + 1}',
      ownerId: 'user-1',
      title: title,
      description: description,
      isPublic: isPublic,
      createdAt: DateTime(2026, 7, 25),
    );
    playlists = [...playlists, playlist];
    return playlist;
  }

  @override
  Future<Playlist> update({
    required String playlistId,
    String? title,
    String? description,
    bool? isPublic,
    String? coverPath,
    bool clearCover = false,
  }) async {
    calls.add('update:$playlistId');
    if (throwOnWrite) throw const PlaylistException('Échec simulé.');
    final index = playlists.indexWhere((p) => p.id == playlistId);
    final updated = playlists[index].copyWith(
      title: title,
      description: description,
      isPublic: isPublic,
      coverPath: coverPath,
      clearCover: clearCover,
    );
    playlists = [...playlists]..[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String playlistId) async {
    calls.add('delete:$playlistId');
    if (throwOnWrite) throw const PlaylistException('Échec simulé.');
    playlists = playlists.where((p) => p.id != playlistId).toList();
  }

  @override
  Future<String> uploadCover({
    required String userId,
    required String playlistId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    calls.add('uploadCover:$playlistId');
    if (throwOnWrite || throwOnCoverUpload) {
      throw const PlaylistException('Échec simulé.');
    }
    return '$userId/$playlistId.$fileExtension';
  }

  @override
  Future<void> removeCoverFile(String storagePath) async {
    calls.add('removeCoverFile:$storagePath');
  }

  @override
  Future<String?> signedCoverUrl(String? storagePath) async {
    calls.add('signedCoverUrl:$storagePath');
    if (storagePath == null || storagePath.isEmpty) return null;
    return 'https://example.test/$storagePath';
  }

  @override
  Future<void> addVideo({
    required String playlistId,
    required String videoId,
  }) async {
    calls.add('addVideo:$playlistId:$videoId');
    if (throwOnWrite) throw const PlaylistException('Échec simulé.');
  }

  @override
  Future<void> removeVideo({
    required String playlistId,
    required String videoId,
  }) async {
    calls.add('removeVideo:$playlistId:$videoId');
    if (throwOnWrite) throw const PlaylistException('Échec simulé.');
    final list = items[playlistId];
    if (list != null) {
      items = {
        ...items,
        playlistId: list.where((v) => v.id != videoId).toList(),
      };
    }
  }

  @override
  Future<void> reorder({
    required String playlistId,
    required List<String> videoIds,
  }) async {
    calls.add('reorder:$playlistId:${videoIds.join(",")}');
    if (throwOnWrite) throw const PlaylistException('Échec simulé.');
  }

  @override
  Future<List<Video>> fetchHistory({int limit = 50}) async {
    calls.add('fetchHistory');
    if (throwOnFetch) throw Exception('échec réseau simulé');
    return history;
  }
}
