import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/media_limits.dart';
import '../../../core/utils/dev_log.dart';
import '../../video/domain/video.dart';
import '../domain/playlist.dart';

/// Contrat d'accès aux playlists et à l'historique de lecture.
///
/// `item_count` n'est jamais écrit ici : il est maintenu par trigger SQL
/// (règle n°6 de CLAUDE.md).
abstract class PlaylistRepository {
  /// Playlists de l'utilisateur courant, plus récentes d'abord.
  Future<List<Playlist>> fetchMine();

  /// Une playlist par son identifiant (null si elle n'est pas visible).
  Future<Playlist?> fetchById(String playlistId);

  /// Clips d'une playlist, dans l'ordre choisi par son propriétaire.
  Future<List<Video>> fetchItems(String playlistId);

  Future<Playlist> create({
    required String title,
    String? description,
    bool isPublic = false,
  });

  Future<Playlist> update({
    required String playlistId,
    String? title,
    String? description,
    bool? isPublic,
    String? coverPath,
    bool clearCover = false,
  });

  Future<void> delete(String playlistId);

  /// Téléverse la couverture et renvoie son chemin de stockage.
  ///
  /// [playlistId] doit déjà exister (le chemin en dépend, convention
  /// `<uid>/<playlist_id>.<ext>`) : appeler après [create], jamais avant.
  Future<String> uploadCover({
    required String userId,
    required String playlistId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  });

  /// Supprime un fichier de couverture devenu inutile (remplacement, retrait).
  Future<void> removeCoverFile(String storagePath);

  /// URL signée temporaire pour afficher une couverture de playlist.
  Future<String?> signedCoverUrl(String? storagePath);

  /// Ajoute un clip à la fin de la playlist.
  Future<void> addVideo({required String playlistId, required String videoId});

  Future<void> removeVideo({
    required String playlistId,
    required String videoId,
  });

  /// Réécrit l'ordre complet de la playlist.
  ///
  /// Passe par la RPC `reorder_playlist`, qui vérifie la propriété et réécrit
  /// toutes les positions en une transaction : la faire à coups d'UPDATE
  /// depuis le client laisserait des ordres incohérents en cas d'échec.
  Future<void> reorder({
    required String playlistId,
    required List<String> videoIds,
  });

  /// Historique de lecture de l'utilisateur courant, plus récent d'abord.
  Future<List<Video>> fetchHistory({int limit = 50});
}

/// Erreur de manipulation de playlist, porteuse d'un message affichable.
class PlaylistException implements Exception {
  const PlaylistException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupabasePlaylistRepository implements PlaylistRepository {
  SupabasePlaylistRepository(this._client);

  final SupabaseClient _client;

  static const String _playlistsTable = 'playlists';
  static const String _itemsTable = 'playlist_items';
  static const String _viewEventsTable = 'view_events';
  static const String _coversBucket = 'playlist-covers';

  /// Clip joint avec son artiste, comme dans `VideoRepository`.
  static const String _videoWithArtist = '''
    video:videos (
      *,
      artist:profiles!videos_artist_id_fkey (
        id, username, display_name, avatar_url, role, subscriber_count
      )
    )
  ''';

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const PlaylistException('Connecte-toi pour gérer tes playlists.');
    }
    return id;
  }

  @override
  Future<List<Playlist>> fetchMine() async {
    final rows = await _client
        .from(_playlistsTable)
        .select()
        .eq('owner_id', _userId)
        .order('created_at', ascending: false);
    return rows.map<Playlist>(Playlist.fromJson).toList();
  }

  @override
  Future<Playlist?> fetchById(String playlistId) async {
    final row = await _client
        .from(_playlistsTable)
        .select()
        .eq('id', playlistId)
        .maybeSingle();
    return row == null ? null : Playlist.fromJson(row);
  }

  @override
  Future<List<Video>> fetchItems(String playlistId) async {
    final rows = await _client
        .from(_itemsTable)
        .select('position, $_videoWithArtist')
        .eq('playlist_id', playlistId)
        .order('position');

    return rows
        .map((row) => row['video'])
        .whereType<Map<String, dynamic>>()
        .map(Video.fromJson)
        .toList();
  }

  @override
  Future<Playlist> create({
    required String title,
    String? description,
    bool isPublic = false,
  }) async {
    final trimmed = description?.trim();
    final row = await _client
        .from(_playlistsTable)
        .insert({
          'owner_id': _userId,
          'title': title.trim(),
          if (trimmed != null && trimmed.isNotEmpty) 'description': trimmed,
          'is_public': isPublic,
        })
        .select()
        .single();
    return Playlist.fromJson(row);
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
    try {
      final row = await _client
          .from(_playlistsTable)
          .update({
            'title': ?title?.trim(),
            'description': ?description?.trim(),
            'is_public': ?isPublic,
            if (clearCover) 'cover_path': null else 'cover_path': ?coverPath,
          })
          .eq('id', playlistId)
          .select()
          .single();
      return Playlist.fromJson(row);
    } on PostgrestException catch (e) {
      logError('mise à jour de playlist impossible', e);
      throw const PlaylistException('L\'opération a échoué. Réessaie.');
    }
  }

  @override
  Future<void> delete(String playlistId) async {
    await _client.from(_playlistsTable).delete().eq('id', playlistId);
  }

  @override
  Future<String> uploadCover({
    required String userId,
    required String playlistId,
    required Uint8List bytes,
    required String fileExtension,
    required String contentType,
  }) async {
    // Premier segment = auth.uid() : exigé par la RLS du bucket.
    final path = '$userId/$playlistId.$fileExtension';
    try {
      await _client.storage
          .from(_coversBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
    } on StorageException catch (e) {
      logError('téléversement de couverture impossible', e);
      throw const PlaylistException(
        'L\'image n\'a pas pu être envoyée. Réessaie.',
      );
    }
    return path;
  }

  @override
  Future<void> removeCoverFile(String storagePath) async {
    if (storagePath.isEmpty) return;
    try {
      await _client.storage.from(_coversBucket).remove([storagePath]);
    } on StorageException catch (e) {
      // Non bloquant : un fichier orphelin dans un bucket privé n'expose rien.
      logError('suppression de couverture impossible', e);
    }
  }

  @override
  Future<String?> signedCoverUrl(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    try {
      return await _client.storage
          .from(_coversBucket)
          .createSignedUrl(storagePath, MediaLimits.signedUrlTtlSeconds);
    } on StorageException catch (e) {
      logError('URL signée de couverture impossible', e);
      return null;
    }
  }

  @override
  Future<void> addVideo({
    required String playlistId,
    required String videoId,
  }) async {
    // La position finale est recalculée : on prend la dernière connue + 1.
    final last = await _client
        .from(_itemsTable)
        .select('position')
        .eq('playlist_id', playlistId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPosition = ((last?['position'] as num?)?.toInt() ?? -1) + 1;

    try {
      await _client.from(_itemsTable).insert({
        'playlist_id': playlistId,
        'video_id': videoId,
        'position': nextPosition,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const PlaylistException('Ce clip est déjà dans la playlist.');
      }
      throw const PlaylistException('L\'ajout a échoué. Réessaie.');
    }
  }

  @override
  Future<void> removeVideo({
    required String playlistId,
    required String videoId,
  }) async {
    await _client
        .from(_itemsTable)
        .delete()
        .eq('playlist_id', playlistId)
        .eq('video_id', videoId);
  }

  @override
  Future<void> reorder({
    required String playlistId,
    required List<String> videoIds,
  }) async {
    await _client.rpc(
      'reorder_playlist',
      params: {'p_playlist_id': playlistId, 'p_video_ids': videoIds},
    );
  }

  @override
  Future<List<Video>> fetchHistory({int limit = 50}) async {
    // `view_events` n'expose que ses propres lignes (RLS) : pas besoin de
    // filtrer sur l'utilisateur, mais on le fait quand même pour la lisibilité
    // du plan de requête.
    final rows = await _client
        .from(_viewEventsTable)
        .select('created_at, $_videoWithArtist')
        .eq('user_id', _userId)
        .order('created_at', ascending: false)
        .limit(limit);

    // Un même clip peut avoir plusieurs vues : l'historique n'affiche que la
    // plus récente de chacun.
    final seen = <String>{};
    final videos = <Video>[];
    for (final row in rows) {
      final json = row['video'];
      if (json is! Map<String, dynamic>) continue;
      final video = Video.fromJson(json);
      if (seen.add(video.id)) videos.add(video);
    }
    return videos;
  }
}
