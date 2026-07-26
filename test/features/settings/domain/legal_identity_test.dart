import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/settings/domain/legal_identity.dart';

void main() {
  group('LegalIdentity.fromJson', () {
    final validJson = <String, dynamic>{
      'user_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'legal_first_name': 'Joemi',
      'legal_last_name': 'Tete',
      'legal_middle_name': 'Kalonji',
      'updated_at': '2026-07-26T10:00:00Z',
    };

    test('mappe correctement un JSON nominal', () {
      final identity = LegalIdentity.fromJson(validJson);
      expect(identity.userId, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(identity.legalFirstName, 'Joemi');
      expect(identity.legalLastName, 'Tete');
      expect(identity.legalMiddleName, 'Kalonji');
      expect(identity.updatedAt, DateTime.parse('2026-07-26T10:00:00Z'));
    });

    test('legal_middle_name absent → null', () {
      final json = Map<String, dynamic>.from(validJson)
        ..remove('legal_middle_name');
      final identity = LegalIdentity.fromJson(json);
      expect(identity.legalMiddleName, isNull);
    });

    test('user_id manquant → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)..remove('user_id');
      expect(() => LegalIdentity.fromJson(json), throwsFormatException);
    });

    test('legal_first_name manquant → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)
        ..remove('legal_first_name');
      expect(() => LegalIdentity.fromJson(json), throwsFormatException);
    });

    test('legal_first_name vide (espaces) → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)
        ..['legal_first_name'] = '   ';
      expect(() => LegalIdentity.fromJson(json), throwsFormatException);
    });

    test('legal_last_name manquant → FormatException', () {
      final json = Map<String, dynamic>.from(validJson)
        ..remove('legal_last_name');
      expect(() => LegalIdentity.fromJson(json), throwsFormatException);
    });

    test('updated_at absent ou invalide → null (non bloquant)', () {
      final json = Map<String, dynamic>.from(validJson)
        ..['updated_at'] = 'pas-une-date';
      expect(LegalIdentity.fromJson(json).updatedAt, isNull);
    });
  });

  group('LegalIdentity.toJson', () {
    test('n\'inclut jamais updated_at (posé côté base)', () {
      const identity = LegalIdentity(
        userId: 'id',
        legalFirstName: 'Joemi',
        legalLastName: 'Tete',
      );
      expect(identity.toJson().containsKey('updated_at'), isFalse);
    });

    test('round-trip fromJson→toJson→fromJson conserve les champs saisis', () {
      final i1 = LegalIdentity.fromJson({
        'user_id': 'id',
        'legal_first_name': 'Joemi',
        'legal_last_name': 'Tete',
        'legal_middle_name': 'Kalonji',
      });
      final json = i1.toJson()..['updated_at'] = null;
      final i2 = LegalIdentity.fromJson(json);
      expect(i2.userId, i1.userId);
      expect(i2.legalFirstName, i1.legalFirstName);
      expect(i2.legalLastName, i1.legalLastName);
      expect(i2.legalMiddleName, i1.legalMiddleName);
    });
  });

  group('LegalIdentity equality', () {
    test('deux identités avec les mêmes champs sont égales', () {
      const a = LegalIdentity(
        userId: 'id',
        legalFirstName: 'Joemi',
        legalLastName: 'Tete',
      );
      const b = LegalIdentity(
        userId: 'id',
        legalFirstName: 'Joemi',
        legalLastName: 'Tete',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
