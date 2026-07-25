import 'package:flutter_test/flutter_test.dart';
import 'package:vibeo/features/social/domain/report_reason.dart';

void main() {
  group('ReportReason.value / label', () {
    test('chaque motif porte une valeur anglaise et un libellé français', () {
      const expected = {
        ReportReason.spam: 'spam',
        ReportReason.hateSpeech: 'hate_speech',
        ReportReason.sexualContent: 'sexual_content',
        ReportReason.violence: 'violence',
        ReportReason.copyright: 'copyright',
        ReportReason.misinformation: 'misinformation',
        ReportReason.other: 'other',
      };

      for (final entry in expected.entries) {
        expect(entry.key.value, entry.value);
        expect(entry.key.label, isNotEmpty);
      }
    });

    test('les valeurs sont toutes distinctes (pas de doublon SQL)', () {
      final values = ReportReason.values.map((r) => r.value).toSet();
      expect(values.length, ReportReason.values.length);
    });
  });

  group('ReportReason.fromString', () {
    for (final reason in ReportReason.values) {
      test('retrouve ${reason.name} depuis "${reason.value}"', () {
        expect(ReportReason.fromString(reason.value), reason);
      });
    }

    test('retombe sur "other" pour une valeur inconnue', () {
      expect(ReportReason.fromString('n-importe-quoi'), ReportReason.other);
    });

    test('retombe sur "other" pour null', () {
      expect(ReportReason.fromString(null), ReportReason.other);
    });

    test('retombe sur "other" pour une chaîne vide', () {
      expect(ReportReason.fromString(''), ReportReason.other);
    });
  });
}
