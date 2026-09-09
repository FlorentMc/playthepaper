import 'package:playthepaper/core/edition_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditionClock', () {
    test('03:59 UTC belongs to the previous day', () {
      final d = EditionClock.editionDateFor(DateTime.utc(2026, 9, 9, 3, 59));
      expect(d, DateTime.utc(2026, 9, 8));
    });

    test('04:00 UTC opens the new edition', () {
      final d = EditionClock.editionDateFor(DateTime.utc(2026, 9, 9, 4, 0));
      expect(d, DateTime.utc(2026, 9, 9));
    });

    test('local time is converted to UTC first', () {
      // 23:30 in UTC-5 on the 8th is 04:30 UTC on the 9th.
      final local = DateTime.utc(2026, 9, 9, 4, 30).toLocal();
      expect(EditionClock.editionDateFor(local), DateTime.utc(2026, 9, 9));
    });

    test('month and year boundaries', () {
      expect(EditionClock.editionDateFor(DateTime.utc(2027, 1, 1, 2)), DateTime.utc(2026, 12, 31));
      expect(EditionClock.editionDateFor(DateTime.utc(2026, 3, 1, 3, 59)), DateTime.utc(2026, 2, 28));
    });

    test('next boundary', () {
      expect(EditionClock.nextBoundaryAfter(DateTime.utc(2026, 9, 8)), DateTime.utc(2026, 9, 9, 4));
      expect(EditionClock.nextBoundaryAfter(DateTime.utc(2026, 12, 31)), DateTime.utc(2027, 1, 1, 4));
    });

    test('untilNextEdition uses the injected clock', () {
      final clock = EditionClock(now: () => DateTime.utc(2026, 9, 8, 22));
      expect(clock.today(), DateTime.utc(2026, 9, 8));
      expect(clock.untilNextEdition(), const Duration(hours: 6));
    });

    test('format and parse round trip', () {
      expect(EditionClock.formatDate(DateTime.utc(2026, 1, 5)), '2026-01-05');
      expect(EditionClock.parseDate('2026-01-05'), DateTime.utc(2026, 1, 5));
    });

    test('parse rejects invalid dates', () {
      expect(() => EditionClock.parseDate('2026-02-30'), throwsFormatException);
      expect(() => EditionClock.parseDate('2026-13-01'), throwsFormatException);
      expect(() => EditionClock.parseDate('26-1-1'), throwsFormatException);
      expect(() => EditionClock.parseDate('2026-01-01T00:00'), throwsFormatException);
    });
  });
}
