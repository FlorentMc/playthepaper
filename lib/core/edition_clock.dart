/// Edition dates roll over at a single shared boundary of 04:00 UTC.
///
/// An edition date is a calendar day in UTC. The edition for a given instant
/// is the UTC date of that instant shifted back by four hours, so 03:59 UTC on
/// the 9th still belongs to the edition of the 8th.
class EditionClock {
  const EditionClock({this.now});

  /// Injectable clock for tests. Must return a UTC instant when provided.
  final DateTime Function()? now;

  static const int boundaryHourUtc = 4;

  DateTime _nowUtc() => (now?.call() ?? DateTime.now()).toUtc();

  /// The edition date (a UTC midnight) active at [instant].
  static DateTime editionDateFor(DateTime instant) {
    final utc = instant.toUtc().subtract(const Duration(hours: boundaryHourUtc));
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// The current edition date.
  DateTime today() => editionDateFor(_nowUtc());

  /// The instant at which the edition following [editionDate] opens.
  static DateTime nextBoundaryAfter(DateTime editionDate) {
    final d = editionDate.toUtc();
    return DateTime.utc(d.year, d.month, d.day + 1, boundaryHourUtc);
  }

  /// Time remaining until the next edition opens.
  Duration untilNextEdition() => nextBoundaryAfter(today()).difference(_nowUtc());

  /// Formats a UTC date as `YYYY-MM-DD`.
  static String formatDate(DateTime date) {
    final d = date.toUtc();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Parses a `YYYY-MM-DD` string into a UTC midnight. Rejects anything else.
  static DateTime parseDate(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) throw FormatException('Invalid edition date: $text');
    final y = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final d = int.parse(match.group(3)!);
    final date = DateTime.utc(y, m, d);
    if (date.year != y || date.month != m || date.day != d) {
      throw FormatException('Invalid edition date: $text');
    }
    return date;
  }
}
