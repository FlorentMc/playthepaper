import 'dart:convert';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'merge_bot.dart';
import 'merge_puzzle.dart';
import 'merge_rules.dart';

/// Deterministic daily seeds: the same date always deals the same game, on
/// any platform.
///
/// A seed is only a deal, so the generator's job is to throw out a bad deal.
/// Each candidate is played to the end by [MergeBot], the fixed reference
/// player, and kept only when that run lasts [minMoves] pushes and reaches
/// [minBestTile] — the better half of deals. A seed that stalls the
/// reference player early is one that deals four after four into a cramped
/// board, and the day would be over before it had begun.
class MergeGenerator {
  MergeGenerator();

  static const int dailySize = 4;
  static const int maxAttempts = 400;

  /// The bar a deal must clear when the reference player takes it.
  static const int minMoves = 200;
  static const int minBestTile = 256;

  /// A stable seed for a date, from `merge-<date>`.
  static int seedFor(String date) => MergeRandom.normalise(fnv1a('merge-$date'));

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
      id: PuzzleId(game: GameKind.merge, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    final parsed = MergePuzzle.parse(check.payload, check.reveal);
    if (parsed.seed != puzzle.seed || parsed.size != puzzle.size) {
      throw StateError('Round trip failed for ${record.id}');
    }
    return record;
  }

  static MergePuzzle generatePuzzle({required int seed, int size = dailySize}) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final puzzle = MergePuzzle(seed: MergeRandom.normalise(_derive(seed, attempt)), size: size);
      if (accepts(MergeBot.play(puzzle))) return puzzle;
    }
    throw StateError('No merge deal found for seed $seed in $maxAttempts attempts');
  }

  /// True when the reference player's game is long enough and gets far
  /// enough for the deal to be worth publishing.
  static bool accepts(MergeRun run) => run.moves >= minMoves && run.bestTile >= minBestTile;

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);
}
