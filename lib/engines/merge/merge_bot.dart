import 'merge_puzzle.dart';
import 'merge_rules.dart';

/// What a reference game came to.
class MergeRun {
  const MergeRun({
    required this.moves,
    required this.score,
    required this.bestTile,
    required this.merges,
    required this.stuck,
  });

  final int moves;
  final int score;
  final int bestTile;

  /// How many merges the run made, a plain measure of how far it got.
  final int merges;

  /// True when the run ended because no push would change the board.
  final bool stuck;

  @override
  String toString() => '$moves moves · $score points · best tile $bestTile';
}

/// A reference player used to check a seed before it is published.
///
/// It deals the opening itself from the seed and drives the board through
/// [MergeRules] alone, so it never borrows the state class's own bookkeeping.
/// Its policy is fixed — try left, then up, then right, then down, and take
/// the first push that changes the board — which is the corner strategy a
/// beginner falls into. Because it never varies, the run it gets is a
/// property of the seed, and a seed whose run is short or low is a seed that
/// deals badly.
class MergeBot {
  const MergeBot._();

  static const List<MergeDirection> policy = [
    MergeDirection.left,
    MergeDirection.up,
    MergeDirection.right,
    MergeDirection.down,
  ];

  static const int maxMoves = 20000;

  static MergeRun play(MergePuzzle puzzle) => playSeed(seed: puzzle.seed, size: puzzle.size);

  static MergeRun playSeed({required int seed, int size = 4}) {
    final random = MergeRandom(seed);
    var tiles = MergeRules.opening(random, size);
    var score = 0;
    var moves = 0;
    var merges = 0;
    while (moves < maxMoves && MergeRules.hasMove(tiles, size)) {
      MergeSlide? chosen;
      for (final direction in policy) {
        final slide = MergeRules.slide(tiles, size, direction);
        if (slide.changed) {
          chosen = slide;
          break;
        }
      }
      if (chosen == null) break;
      tiles = List<int>.of(chosen.tiles, growable: false);
      score += chosen.gained;
      merges += chosen.merged.length;
      MergeRules.spawn(tiles, random);
      moves++;
    }
    return MergeRun(
      moves: moves,
      score: score,
      bestTile: MergeRules.bestTile(tiles),
      merges: merges,
      stuck: !MergeRules.hasMove(tiles, size),
    );
  }

  /// Replays a fixed list of pushes from a seed, for tests that need a game
  /// they can predict move by move.
  static MergeRun replay({required int seed, int size = 4, required List<MergeDirection> moves}) {
    final random = MergeRandom(seed);
    var tiles = MergeRules.opening(random, size);
    var score = 0;
    var played = 0;
    var merges = 0;
    for (final direction in moves) {
      if (!MergeRules.hasMove(tiles, size)) break;
      final slide = MergeRules.slide(tiles, size, direction);
      if (!slide.changed) continue;
      tiles = List<int>.of(slide.tiles, growable: false);
      score += slide.gained;
      merges += slide.merged.length;
      MergeRules.spawn(tiles, random);
      played++;
    }
    return MergeRun(
      moves: played,
      score: score,
      bestTile: MergeRules.bestTile(tiles),
      merges: merges,
      stuck: !MergeRules.hasMove(tiles, size),
    );
  }
}
