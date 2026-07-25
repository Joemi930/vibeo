import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/core/router/app_routes.dart';

void main() {
  test('video(id) construit le chemin /video/:id', () {
    expect(AppRoutes.video('abc'), '/video/abc');
  });

  test('artist(id) construit le chemin /artist/:id', () {
    expect(AppRoutes.artist('x'), '/artist/x');
  });

  group('isPublic', () {
    for (final loc in ['/', '/search', '/video/1', '/artist/1']) {
      test('$loc est public', () {
        expect(AppRoutes.isPublic(loc), isTrue);
      });
    }

    for (final loc in [
      '/library',
      '/profile',
      '/settings',
      '/studio',
      '/upload',
      '/admin',
    ]) {
      test('$loc n\'est pas public', () {
        expect(AppRoutes.isPublic(loc), isFalse);
      });
    }
  });
}
