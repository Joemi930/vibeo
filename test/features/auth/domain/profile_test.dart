import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/auth/domain/profile.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';

void main() {
  group('Profile.fromJson', () {
    final validJson = <String, dynamic>{
      'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'username': 'naika',
      'display_name': 'Naïka',
      'avatar_url': 'naika/avatar.jpg',
      'bio': 'Chanteuse',
      'role': 'artist',
      'created_at': '2026-01-15T10:00:00Z',
    };

    test('mappe correctement un JSON nominal', () {
      final p = Profile.fromJson(validJson);
      expect(p.id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(p.username, 'naika');
      expect(p.displayName, 'Naïka');
      expect(p.avatarUrl, 'naika/avatar.jpg');
      expect(p.bio, 'Chanteuse');
      expect(p.role, UserRole.artist);
      expect(p.createdAt, DateTime.parse('2026-01-15T10:00:00Z'));
    });

    test('champs optionnels absents → null, rôle par défaut listener', () {
      final p = Profile.fromJson({
        'id': 'id-1',
        'username': 'bob',
        'created_at': '2026-01-01T00:00:00Z',
      });
      expect(p.displayName, isNull);
      expect(p.avatarUrl, isNull);
      expect(p.bio, isNull);
      expect(p.role, UserRole.listener);
    });

    test('id manquant → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)..remove('id');
      expect(() => Profile.fromJson(json), throwsFormatException);
    });

    test('username manquant → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)..remove('username');
      expect(() => Profile.fromJson(json), throwsFormatException);
    });

    test('created_at manquant → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)..remove('created_at');
      expect(() => Profile.fromJson(json), throwsFormatException);
    });

    test('id de type invalide → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)..['id'] = 42;
      expect(() => Profile.fromJson(json), throwsFormatException);
    });

    test('created_at non parsable → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)
        ..['created_at'] = 'pas-une-date';
      expect(() => Profile.fromJson(json), throwsFormatException);
    });

    test('rôle inconnu → listener (fallback)', () {
      final json = Map<String, dynamic>.from(validJson)..['role'] = 'wizard';
      expect(Profile.fromJson(json).role, UserRole.listener);
    });
  });

  group('Profile.toJson', () {
    test('n\'inclut jamais le rôle (protégé côté base)', () {
      final p = Profile(
        id: 'id',
        username: 'naika',
        role: UserRole.admin,
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );
      expect(p.toJson().containsKey('role'), isFalse);
    });

    test('round-trip fromJson→toJson→fromJson conserve les champs', () {
      final p1 = Profile.fromJson({
        'id': 'id',
        'username': 'naika',
        'display_name': 'Naïka',
        'bio': 'Bio',
        'created_at': '2026-01-01T00:00:00Z',
      });
      final p2 = Profile.fromJson(p1.toJson());
      expect(p2, p1);
    });
  });

  group('Profile helpers', () {
    test('resolvedName privilégie display_name, sinon username', () {
      final base = Profile(
        id: 'id',
        username: 'naika',
        role: UserRole.listener,
        createdAt: DateTime(2026),
      );
      expect(base.resolvedName, 'naika');
      expect(base.copyWith(displayName: 'Naïka').resolvedName, 'Naïka');
      expect(base.copyWith(displayName: '   ').resolvedName, 'naika');
    });

    test('isArtist / isAdmin', () {
      final p = Profile(
        id: 'id',
        username: 'x',
        role: UserRole.artist,
        createdAt: DateTime(2026),
      );
      expect(p.isArtist, isTrue);
      expect(p.isAdmin, isFalse);
    });
  });
}
