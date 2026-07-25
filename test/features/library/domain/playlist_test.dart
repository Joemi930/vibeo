import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/library/domain/playlist.dart';

void main() {
  final validJson = <String, dynamic>{
    'id': 'playlist-1',
    'owner_id': 'user-1',
    'title': 'Nuit & basse',
    'created_at': '2026-07-01T00:00:00.000Z',
  };

  group('Playlist.fromJson', () {
    test('construit une playlist à partir d\'un JSON nominal', () {
      final playlist = Playlist.fromJson(validJson);

      expect(playlist.id, 'playlist-1');
      expect(playlist.ownerId, 'user-1');
      expect(playlist.title, 'Nuit & basse');
      expect(playlist.description, isNull);
      expect(playlist.isPublic, isFalse);
      expect(playlist.itemCount, 0);
      expect(playlist.updatedAt, isNull);
      expect(playlist.createdAt, DateTime.parse('2026-07-01T00:00:00.000Z'));
    });

    test('lit les champs optionnels quand présents', () {
      final json = {
        ...validJson,
        'description': 'Mes sons préférés.',
        'is_public': true,
        'item_count': 12,
        'updated_at': '2026-07-05T00:00:00.000Z',
      };

      final playlist = Playlist.fromJson(json);

      expect(playlist.description, 'Mes sons préférés.');
      expect(playlist.isPublic, isTrue);
      expect(playlist.itemCount, 12);
      expect(playlist.updatedAt, DateTime.parse('2026-07-05T00:00:00.000Z'));
    });

    test('item_count accepte un double JSON (num) et l\'arrondit en int', () {
      final json = {...validJson, 'item_count': 3.0};
      expect(Playlist.fromJson(json).itemCount, 3);
    });

    test('ignore un updated_at d\'un type invalide', () {
      final json = {...validJson, 'updated_at': 999};
      expect(Playlist.fromJson(json).updatedAt, isNull);
    });

    for (final field in ['id', 'owner_id', 'title', 'created_at']) {
      test('lève FormatException si "$field" est absent', () {
        final json = {...validJson}..remove(field);
        expect(() => Playlist.fromJson(json), throwsFormatException);
      });

      test('lève FormatException si "$field" est d\'un type invalide', () {
        final json = {...validJson, field: 1234};
        expect(() => Playlist.fromJson(json), throwsFormatException);
      });

      test('lève FormatException si "$field" est une chaîne vide', () {
        final json = {...validJson, field: ''};
        expect(() => Playlist.fromJson(json), throwsFormatException);
      });
    }

    test('lève FormatException si created_at n\'est pas une date valide', () {
      final json = {...validJson, 'created_at': 'nawak'};
      expect(() => Playlist.fromJson(json), throwsFormatException);
    });
  });

  group('Playlist.toJson', () {
    test('sérialise uniquement les champs modifiables (jamais item_count)', () {
      final playlist = Playlist.fromJson({
        ...validJson,
        'item_count': 42,
        'is_public': true,
        'description': 'Une description',
      });

      expect(playlist.toJson(), {
        'owner_id': 'user-1',
        'title': 'Nuit & basse',
        'description': 'Une description',
        'is_public': true,
      });
    });
  });

  group('Playlist.copyWith', () {
    final playlist = Playlist.fromJson({
      ...validJson,
      'description': 'Description initiale',
      'is_public': false,
      'item_count': 5,
    });

    test('remplace le titre, la description et la visibilité', () {
      final updated = playlist.copyWith(
        title: 'Nouveau titre',
        description: 'Nouvelle description',
        isPublic: true,
      );

      expect(updated.title, 'Nouveau titre');
      expect(updated.description, 'Nouvelle description');
      expect(updated.isPublic, isTrue);
      // Inchangés.
      expect(updated.id, playlist.id);
      expect(updated.itemCount, playlist.itemCount);
    });

    test('sans argument, préserve tous les champs', () {
      expect(playlist.copyWith(), playlist);
    });

    test(
      'clearDescription efface la description même si une nouvelle est fournie',
      () {
        final cleared = playlist.copyWith(
          description: 'ignorée',
          clearDescription: true,
        );
        expect(cleared.description, isNull);
      },
    );

    test(
      'itemCount peut être mis à jour explicitement (usage interne trigger)',
      () {
        final updated = playlist.copyWith(itemCount: 9);
        expect(updated.itemCount, 9);
      },
    );
  });

  group('Playlist == / hashCode', () {
    test('deux playlists avec les mêmes champs sont égales', () {
      final a = Playlist.fromJson(validJson);
      final b = Playlist.fromJson(validJson);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('un titre différent rend les playlists inégales', () {
      final a = Playlist.fromJson(validJson);
      final b = Playlist.fromJson({...validJson, 'title': 'Autre titre'});
      expect(a, isNot(b));
    });
  });
}
