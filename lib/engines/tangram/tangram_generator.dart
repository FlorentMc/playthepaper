import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'tangram_puzzle.dart';
import 'tangram_silhouettes.dart';

/// Picks the day's figure from the authored set, dealing the whole set into a
/// fresh order for each round so nothing repeats until every figure has been
/// seen. The order comes from an FNV-1a seed, so the same date gives the same
/// figure on every platform.
class TangramGenerator {
  TangramGenerator({List<TangramSilhouette>? silhouettes})
      : silhouettes = silhouettes ?? tangramSilhouettes;

  final List<TangramSilhouette> silhouettes;
  List<TangramSilhouette>? _passing;
  final Map<int, List<TangramSilhouette>> _rounds = {};

  /// An outline with fewer corners than this is a bare geometric shape
  /// rather than a figure, and gives a player nothing to take hold of.
  static const int minCorners = 6;

  /// Past this, the outline shows where the pieces meet and the puzzle
  /// solves itself.
  static const int maxCorners = 16;

  /// Rotation counts from here.
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  static int seedFor(DateTime date) => fnv1a('tangram-${EditionClock.formatDate(date)}');

  /// 32-bit FNV-1a over the code units of [text]; ASCII in practice.
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Why [silhouette] cannot be published, or null when it passes: seven
  /// pieces that do not overlap, one closed outline with no hole, and a
  /// corner count in the publishable band.
  static String? problem(TangramSilhouette silhouette) {
    final TangramPuzzle puzzle;
    try {
      puzzle = silhouette.centred().toPuzzle();
    } on FormatException catch (e) {
      return e.message;
    }
    if (puzzle.outline.length != 1) return '${puzzle.outline.length} separate contours';
    final corners = puzzle.outline.first.length;
    if (corners < minCorners) return 'too plain: $corners corners';
    if (corners > maxCorners) return 'gives itself away: $corners corners';
    return null;
  }

  /// The authored figures that pass [problem], in authored order.
  List<TangramSilhouette> get passing =>
      _passing ??= List.unmodifiable(silhouettes.where((s) => problem(s) == null));

  /// Days from [epoch], counting backwards for earlier dates.
  static int ordinalFor(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).difference(epoch).inDays;

  /// The figures of round [round], dealt from a seed of their own.
  List<TangramSilhouette> order(int round) => _rounds.putIfAbsent(round, () {
        final pool = passing;
        if (pool.isEmpty) throw StateError('No tangram silhouette passes the checks');
        return List.unmodifiable(
            List<TangramSilhouette>.of(pool)..shuffle(Random(fnv1a('tangram-round-$round'))));
      });

  TangramSilhouette silhouetteFor(DateTime date) {
    final count = passing.length;
    final ordinal = ordinalFor(date);
    final round = (ordinal / count).floor();
    return order(round)[ordinal - round * count];
  }

  TangramPuzzle puzzleFor(DateTime date) => silhouetteFor(date).centred().toPuzzle();

  PuzzleRecord generate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final puzzle = puzzleFor(day);
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.tangram, date: day),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
    TangramPuzzle.parse(record.payload, record.reveal);
    return record;
  }
}
