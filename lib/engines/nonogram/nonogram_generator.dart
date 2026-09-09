import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'nonogram_pictures.dart';
import 'nonogram_puzzle.dart';
import 'nonogram_solver.dart';

/// Picks the day's picture: 5×5 on odd days of the month, 10×10 on even
/// ones, rotating through every picture of that size that passes the
/// solver's checks before any repeats. The order is dealt once from an
/// FNV-1a seed, so the same date always gives the same picture on every
/// platform.
class NonogramGenerator {
  NonogramGenerator({List<NonogramPicture>? pictures}) : pictures = pictures ?? nonogramPictures;

  final List<NonogramPicture> pictures;
  final Map<int, List<NonogramPicture>> _passing = {};
  final Map<int, List<NonogramPicture>> _orders = {};

  static const int smallSize = 5;
  static const int largeSize = 10;
  static const double minFill = 0.25;
  static const double maxFill = 0.65;

  /// A picture the line solver finishes in one sweep of rows and columns
  /// gives itself away; every published picture needs at least this many.
  static const int minSweeps = 2;

  /// Rotation counts from here.
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  static int sizeFor(DateTime date) => date.day.isOdd ? smallSize : largeSize;

  static int seedFor(DateTime date) => fnv1a('nonogram-${EditionClock.formatDate(date)}');

  /// 32-bit FNV-1a over the UTF-8 bytes of [text]; ASCII in practice.
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Why [picture] cannot be published, or null when it passes: a square of
  /// a supported size, a fill between [minFill] and [maxFill], clues with
  /// exactly one solution that row-and-column logic finds without guessing
  /// in at least [minSweeps] sweeps.
  static String? problem(NonogramPicture picture) {
    final size = picture.size;
    if (size != smallSize && size != largeSize) return 'size $size is not $smallSize or $largeSize';
    if (picture.rows.any((r) => r.length != size)) return 'rows are not all $size wide';
    final NonogramPuzzle puzzle;
    try {
      puzzle = NonogramPuzzle.fromPicture(picture: picture.rows, title: picture.title);
    } on FormatException catch (e) {
      return e.message;
    }
    final fill = puzzle.fillFraction;
    if (fill < minFill || fill > maxFill) return 'fill ${(fill * 100).round()}% is outside ${(minFill * 100).round()}–${(maxFill * 100).round()}%';
    final analysis = NonogramSolver.analyse(puzzle);
    if (!analysis.isUnique) return 'clues have more than one solution';
    if (!analysis.lineSolvable) return 'needs guessing';
    if (analysis.sweeps < minSweeps) return 'trivial: solved in ${analysis.sweeps} sweep';
    return null;
  }

  /// The pictures of [size] that pass [problem], in authored order.
  List<NonogramPicture> passing(int size) =>
      _passing.putIfAbsent(size, () => List.unmodifiable(pictures.where((p) => p.size == size && problem(p) == null)));

  /// Position of [date] among the days that share its size, counted from [epoch].
  static int ordinalFor(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final size = sizeFor(day);
    var n = 0;
    if (day.isBefore(epoch)) {
      for (var d = day; d.isBefore(epoch); d = d.add(const Duration(days: 1))) {
        if (sizeFor(d) == size) n--;
      }
      return n;
    }
    for (var d = epoch; d.isBefore(day); d = d.add(const Duration(days: 1))) {
      if (sizeFor(d) == size) n++;
    }
    return n;
  }

  /// The rotation for [size]: the passing pictures dealt once from a seed.
  List<NonogramPicture> order(int size) => _orders.putIfAbsent(size, () {
        final pool = passing(size);
        if (pool.isEmpty) throw StateError('No $size×$size picture passes the checks');
        return List.unmodifiable(List<NonogramPicture>.of(pool)..shuffle(Random(fnv1a('nonogram-$size'))));
      });

  NonogramPicture pictureFor(DateTime date) {
    final rotation = order(sizeFor(date));
    return rotation[ordinalFor(date) % rotation.length];
  }

  PuzzleRecord generate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final picture = pictureFor(day);
    final puzzle = NonogramPuzzle.fromPicture(picture: picture.rows, title: picture.title);
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.nonogram, date: day),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
    NonogramPuzzle.parse(record.payload, record.reveal);
    return record;
  }
}
