import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/video/domain/video.dart';
import 'package:vibeo/features/video/domain/video_status.dart';

void main() {
  final validJson = <String, dynamic>{
    'id': 'video-1',
    'artist_id': 'artist-1',
    'title': 'Mon premier clip',
    'video_path': 'artist-1/video-1.mp4',
    'created_at': '2026-07-20T10:00:00.000Z',
  };

  group('Video.fromJson', () {
    test('construit un clip à partir d\'un JSON nominal, avec les valeurs '
        'par défaut des champs optionnels', () {
      final video = Video.fromJson(validJson);

      expect(video.id, 'video-1');
      expect(video.artistId, 'artist-1');
      expect(video.title, 'Mon premier clip');
      expect(video.videoPath, 'artist-1/video-1.mp4');
      expect(video.description, isNull);
      expect(video.genreId, isNull);
      expect(video.thumbnailPath, isNull);
      expect(video.durationSeconds, isNull);
      expect(video.sizeBytes, isNull);
      expect(video.status, VideoStatus.processing);
      expect(video.viewCount, 0);
      expect(video.likeCount, 0);
      expect(video.commentCount, 0);
      expect(video.publishedAt, isNull);
      expect(video.artist, isNull);
      expect(video.createdAt, DateTime.parse('2026-07-20T10:00:00.000Z'));
    });

    test('lit tous les champs optionnels quand présents', () {
      final json = {
        ...validJson,
        'description': 'Une description',
        'genre_id': 3,
        'thumbnail_path': 'artist-1/video-1.jpg',
        'duration_seconds': 214,
        'size_bytes': 5242880,
        'status': 'published',
        'view_count': 1234,
        'like_count': 42,
        'comment_count': 7,
        'published_at': '2026-07-21T00:00:00.000Z',
      };

      final video = Video.fromJson(json);

      expect(video.description, 'Une description');
      expect(video.genreId, 3);
      expect(video.thumbnailPath, 'artist-1/video-1.jpg');
      expect(video.durationSeconds, 214);
      expect(video.sizeBytes, 5242880);
      expect(video.status, VideoStatus.published);
      expect(video.viewCount, 1234);
      expect(video.likeCount, 42);
      expect(video.commentCount, 7);
      expect(video.publishedAt, DateTime.parse('2026-07-21T00:00:00.000Z'));
    });

    test(
      'comment_count accepte un double JSON (num) et l\'arrondit en int',
      () {
        final json = {...validJson, 'comment_count': 5.0};
        expect(Video.fromJson(json).commentCount, 5);
      },
    );

    test('lit l\'artiste joint sous la clé "artist"', () {
      final json = {
        ...validJson,
        'artist': {'id': 'artist-1', 'username': 'naika', 'role': 'artist'},
      };
      final video = Video.fromJson(json);
      expect(video.artist, isNotNull);
      expect(video.artist!.resolvedName, 'naika');
    });

    test('lit l\'artiste joint sous la clé "profiles" (alias PostgREST)', () {
      final json = {
        ...validJson,
        'profiles': {'id': 'artist-1', 'username': 'naika', 'role': 'artist'},
      };
      final video = Video.fromJson(json);
      expect(video.artist, isNotNull);
    });

    test('ignore un published_at d\'un type invalide', () {
      final json = {...validJson, 'published_at': 42};
      expect(Video.fromJson(json).publishedAt, isNull);
    });

    test('retombe sur "processing" pour un statut inconnu', () {
      final json = {...validJson, 'status': 'n-importe-quoi'};
      expect(Video.fromJson(json).status, VideoStatus.processing);
    });

    for (final field in [
      'id',
      'artist_id',
      'title',
      'video_path',
      'created_at',
    ]) {
      test('lève FormatException si "$field" est absent', () {
        final json = {...validJson}..remove(field);
        expect(() => Video.fromJson(json), throwsFormatException);
      });

      test('lève FormatException si "$field" est d\'un type invalide', () {
        final json = {...validJson, field: 1234};
        expect(() => Video.fromJson(json), throwsFormatException);
      });

      test('lève FormatException si "$field" est une chaîne vide', () {
        final json = {...validJson, field: ''};
        expect(() => Video.fromJson(json), throwsFormatException);
      });
    }

    test('lève FormatException si created_at n\'est pas une date valide', () {
      final json = {...validJson, 'created_at': 'nawak'};
      expect(() => Video.fromJson(json), throwsFormatException);
    });
  });

  group('Video.toJson', () {
    test('sérialise les champs modifiables, jamais les compteurs', () {
      final video = Video.fromJson({
        ...validJson,
        'view_count': 999,
        'like_count': 50,
        'comment_count': 12,
        'published_at': '2026-07-21T00:00:00.000Z',
      });

      final json = video.toJson();

      expect(json['id'], 'video-1');
      expect(json['artist_id'], 'artist-1');
      expect(json['title'], 'Mon premier clip');
      expect(json['video_path'], 'artist-1/video-1.mp4');
      expect(json.containsKey('view_count'), isFalse);
      expect(json.containsKey('like_count'), isFalse);
      expect(json.containsKey('comment_count'), isFalse);
      expect(json.containsKey('published_at'), isFalse);
    });
  });

  group('Video.duration / isPublished', () {
    test('duration est nul quand durationSeconds est nul', () {
      expect(Video.fromJson(validJson).duration, isNull);
    });

    test('duration convertit durationSeconds en Duration', () {
      final json = {...validJson, 'duration_seconds': 90};
      expect(Video.fromJson(json).duration, const Duration(seconds: 90));
    });

    test('isPublished reflète le statut', () {
      final published = Video.fromJson({...validJson, 'status': 'published'});
      final processing = Video.fromJson(validJson);
      expect(published.isPublished, isTrue);
      expect(processing.isPublished, isFalse);
    });
  });

  group('Video.copyWith', () {
    final base = Video.fromJson({
      ...validJson,
      'description': 'Description initiale',
      'genre_id': 2,
      'view_count': 10,
      'like_count': 2,
      'comment_count': 1,
    });

    test('remplace les champs fournis et préserve les autres', () {
      final updated = base.copyWith(title: 'Nouveau titre', likeCount: 3);

      expect(updated.title, 'Nouveau titre');
      expect(updated.likeCount, 3);
      expect(updated.description, base.description);
      expect(updated.genreId, base.genreId);
      expect(updated.viewCount, base.viewCount);
      expect(updated.commentCount, base.commentCount);
    });

    test('sans argument, préserve tous les champs', () {
      expect(base.copyWith(), base);
    });

    test('clearDescription efface la description même si une nouvelle est '
        'fournie', () {
      final cleared = base.copyWith(
        description: 'ignorée',
        clearDescription: true,
      );
      expect(cleared.description, isNull);
    });

    test('clearGenre efface le genre même si un nouveau est fourni', () {
      final cleared = base.copyWith(genreId: 9, clearGenre: true);
      expect(cleared.genreId, isNull);
    });

    test('clearDescription et clearGenre peuvent s\'appliquer ensemble', () {
      final cleared = base.copyWith(clearDescription: true, clearGenre: true);
      expect(cleared.description, isNull);
      expect(cleared.genreId, isNull);
    });

    test('commentCount peut être mis à jour explicitement (usage interne '
        'trigger)', () {
      final updated = base.copyWith(commentCount: 8);
      expect(updated.commentCount, 8);
    });
  });

  group('Video == / hashCode', () {
    test('deux clips avec les mêmes champs sont égaux', () {
      final a = Video.fromJson(validJson);
      final b = Video.fromJson(validJson);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('un commentCount différent rend les clips inégaux', () {
      final a = Video.fromJson({...validJson, 'comment_count': 1});
      final b = Video.fromJson({...validJson, 'comment_count': 2});
      expect(a, isNot(b));
    });

    test('un titre différent rend les clips inégaux', () {
      final a = Video.fromJson(validJson);
      final b = Video.fromJson({...validJson, 'title': 'Autre titre'});
      expect(a, isNot(b));
    });
  });
}
