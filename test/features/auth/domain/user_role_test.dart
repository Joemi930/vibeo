import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/auth/domain/user_role.dart';

void main() {
  group('UserRole.fromString', () {
    test('valeurs connues', () {
      expect(UserRole.fromString('listener'), UserRole.listener);
      expect(UserRole.fromString('artist'), UserRole.artist);
      expect(UserRole.fromString('admin'), UserRole.admin);
    });

    test('null ou inconnu → listener', () {
      expect(UserRole.fromString(null), UserRole.listener);
      expect(UserRole.fromString('autre'), UserRole.listener);
    });
  });

  test('value renvoie le nom attendu par la base', () {
    expect(UserRole.artist.value, 'artist');
    expect(UserRole.admin.value, 'admin');
    expect(UserRole.listener.value, 'listener');
  });
}
