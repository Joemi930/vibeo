import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';
import 'package:vibeo/features/social/domain/comment.dart';
import 'package:vibeo/features/video/domain/artist_summary.dart';

void main() {
  final validJson = <String, dynamic>{
    'id': 'comment-1',
    'video_id': 'video-1',
    'author_id': 'user-1',
    'body': 'Superbe clip !',
    'created_at': '2026-07-20T10:00:00.000Z',
  };

  group('Comment.fromJson', () {
    test('construit un commentaire à partir d\'un JSON nominal', () {
      final comment = Comment.fromJson(validJson);

      expect(comment.id, 'comment-1');
      expect(comment.videoId, 'video-1');
      expect(comment.authorId, 'user-1');
      expect(comment.body, 'Superbe clip !');
      expect(comment.createdAt, DateTime.parse('2026-07-20T10:00:00.000Z'));
      expect(comment.updatedAt, isNull);
      expect(comment.author, isNull);
    });

    test('lit l\'auteur joint sous la clé "author"', () {
      final json = {
        ...validJson,
        'author': {
          'id': 'user-1',
          'username': 'naika',
          'display_name': 'Naïka',
          'role': 'artist',
        },
      };

      final comment = Comment.fromJson(json);

      expect(comment.author, isNotNull);
      expect(comment.author!.resolvedName, 'Naïka');
      expect(comment.author!.isVerified, isTrue);
    });

    test('lit l\'auteur joint sous la clé "profiles" (alias PostgREST)', () {
      final json = {
        ...validJson,
        'profiles': {'id': 'user-1', 'username': 'naika', 'role': 'listener'},
      };

      final comment = Comment.fromJson(json);

      expect(comment.author, isNotNull);
      expect(comment.author!.resolvedName, 'naika');
    });

    test('lit updated_at quand présent et valide', () {
      final json = {...validJson, 'updated_at': '2026-07-21T09:00:00.000Z'};

      final comment = Comment.fromJson(json);

      expect(comment.updatedAt, DateTime.parse('2026-07-21T09:00:00.000Z'));
    });

    test('ignore un updated_at d\'un type invalide', () {
      final json = {...validJson, 'updated_at': 12345};

      final comment = Comment.fromJson(json);

      expect(comment.updatedAt, isNull);
    });

    for (final field in ['id', 'video_id', 'author_id', 'body', 'created_at']) {
      test('lève FormatException si "$field" est absent', () {
        final json = {...validJson}..remove(field);
        expect(() => Comment.fromJson(json), throwsFormatException);
      });

      test('lève FormatException si "$field" est d\'un type invalide', () {
        final json = {...validJson, field: 42};
        expect(() => Comment.fromJson(json), throwsFormatException);
      });

      if (field != 'created_at') {
        // "created_at" n'a pas de contrainte "chaîne non vide" dédiée : une
        // chaîne vide y est déjà couverte par le test "type invalide" au sens
        // large (`DateTime.tryParse('')` échoue de toute façon).
        test('lève FormatException si "$field" est une chaîne vide', () {
          final json = {...validJson, field: ''};
          expect(() => Comment.fromJson(json), throwsFormatException);
        });
      }
    }

    test('lève FormatException si created_at n\'est pas une date valide', () {
      final json = {...validJson, 'created_at': 'pas-une-date'};
      expect(() => Comment.fromJson(json), throwsFormatException);
    });
  });

  group('Comment.toJson', () {
    test('sérialise uniquement les champs modifiables par le client', () {
      final comment = Comment.fromJson(validJson);

      expect(comment.toJson(), {
        'video_id': 'video-1',
        'author_id': 'user-1',
        'body': 'Superbe clip !',
      });
    });
  });

  group('Comment.isEdited', () {
    test('faux quand updatedAt est nul', () {
      final comment = Comment.fromJson(validJson);
      expect(comment.isEdited, isFalse);
    });

    test('faux quand updatedAt est à moins d\'une seconde de createdAt', () {
      final createdAt = DateTime(2026, 7, 20, 10);
      final comment = Comment(
        id: 'c1',
        videoId: 'v1',
        authorId: 'u1',
        body: 'x',
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(milliseconds: 500)),
      );
      expect(comment.isEdited, isFalse);
    });

    test('vrai quand updatedAt dépasse d\'une seconde createdAt', () {
      final createdAt = DateTime(2026, 7, 20, 10);
      final comment = Comment(
        id: 'c1',
        videoId: 'v1',
        authorId: 'u1',
        body: 'x',
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(seconds: 5)),
      );
      expect(comment.isEdited, isTrue);
    });
  });

  group('Comment.copyWith', () {
    test('remplace le corps et la date de modification', () {
      final comment = Comment.fromJson(validJson);
      final updatedAt = DateTime(2026, 7, 22);

      final edited = comment.copyWith(body: 'Corrigé', updatedAt: updatedAt);

      expect(edited.body, 'Corrigé');
      expect(edited.updatedAt, updatedAt);
      // Les autres champs sont préservés.
      expect(edited.id, comment.id);
      expect(edited.videoId, comment.videoId);
      expect(edited.authorId, comment.authorId);
      expect(edited.createdAt, comment.createdAt);
    });

    test('sans argument, renvoie un commentaire équivalent', () {
      final comment = Comment.fromJson(validJson);
      final copy = comment.copyWith();
      expect(copy, comment);
    });
  });

  group('Comment == / hashCode', () {
    test('deux commentaires avec les mêmes champs clés sont égaux', () {
      final a = Comment.fromJson(validJson);
      final b = Comment.fromJson(validJson);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('l\'auteur joint n\'entre pas dans l\'égalité', () {
      final a = Comment.fromJson(validJson);
      final b = Comment.fromJson({
        ...validJson,
        'author': {'id': 'user-1', 'username': 'naika', 'role': 'artist'},
      });
      expect(a, b);
    });

    test('un id différent rend les commentaires inégaux', () {
      final a = Comment.fromJson(validJson);
      final b = Comment.fromJson({...validJson, 'id': 'comment-2'});
      expect(a, isNot(b));
    });
  });

  test('ArtistSummary jointe conserve son rôle auditeur (non vérifié)', () {
    const summary = ArtistSummary(
      id: 'user-2',
      username: 'fan',
      role: UserRole.listener,
    );
    expect(summary.isVerified, isFalse);
  });
}
