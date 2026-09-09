import 'dart:convert';
import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'target_puzzle.dart';
import 'target_search.dart';

/// Deterministic Target generation: the same date always yields the same
/// tiles and target. Two distinct large tiles and four small ones (at most
/// two of a kind) are drawn, then targets are drawn until the exhaustive
/// search finds one that needs at least [preferredMinTiles] tiles; after
/// [targetDraws] draws a target needing [minTiles] is accepted.
class TargetGenerator {
  TargetGenerator();

  static const int maxAttempts = 100;
  static const int targetDraws = 24;
  static const int preferredMinTiles = 4;
  static const int minTiles = 3;

  /// A stable seed for a date, from `target-<date>`.
  static int seedFor(String date) => fnv1a('target-$date');

  /// Stable 32-bit FNV-1a hash, the same as the content tools use.
  static int fnv1a(String input) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  PuzzleRecord generate(DateTime date) {
    final puzzle = generatePuzzle(seed: seedFor(EditionClock.formatDate(date)));
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.target, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    final parsed = TargetPuzzle.parse(check.payload, check.reveal);
    if (parsed.tiles.join(',') != puzzle.tiles.join(',') ||
        parsed.target != puzzle.target ||
        parsed.solution.text != puzzle.solution.text) {
      throw StateError('Round trip failed for ${record.id}');
    }
    return record;
  }

  static TargetPuzzle generatePuzzle({required int seed}) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final random = Random(_derive(seed, attempt));
      final tiles = drawTiles(random);
      final search = TargetSearch(tiles);
      TargetSolution? fallback;
      int? fallbackTarget;
      for (var draw = 0; draw < targetDraws; draw++) {
        final target = TargetPuzzle.minTarget + random.nextInt(TargetPuzzle.maxTarget - TargetPuzzle.minTarget + 1);
        final solution = search.solve(target);
        if (solution == null) continue;
        if (solution.tilesUsed >= preferredMinTiles) {
          return TargetPuzzle(tiles: tiles, target: target, expression: solution.expression.text);
        }
        if (solution.tilesUsed >= minTiles && fallback == null) {
          fallback = solution;
          fallbackTarget = target;
        }
      }
      if (fallback != null) {
        return TargetPuzzle(tiles: tiles, target: fallbackTarget!, expression: fallback.expression.text);
      }
    }
    throw StateError('No target puzzle found for seed $seed in $maxAttempts attempts');
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// Two distinct large tiles then four small ones from a bag holding two of
  /// each number 1–10, in the order they were drawn.
  static List<int> drawTiles(Random random) {
    final large = List<int>.of(TargetPuzzle.largeTiles)..shuffle(random);
    final bag = [
      for (var n = TargetPuzzle.minSmall; n <= TargetPuzzle.maxSmall; n++) ...[n, n],
    ]..shuffle(random);
    return [...large.take(TargetPuzzle.largeCount), ...bag.take(TargetPuzzle.tileCount - TargetPuzzle.largeCount)];
  }
}
