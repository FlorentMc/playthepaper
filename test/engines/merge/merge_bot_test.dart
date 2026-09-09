import 'package:playthepaper/engines/merge/merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the reference player deals the same opening as the puzzle', () {
    for (var seed = 1; seed <= 30; seed++) {
      final puzzle = MergePuzzle(seed: seed);
      final replay = MergeBot.replay(seed: seed, moves: const []);
      expect(replay.moves, 0, reason: 'seed $seed');
      expect(replay.bestTile, MergeRules.bestTile(puzzle.openingTiles), reason: 'seed $seed');
    }
  });

  test('a run is the same every time and ends stuck', () {
    for (var seed = 100; seed < 110; seed++) {
      final a = MergeBot.playSeed(seed: seed);
      final b = MergeBot.playSeed(seed: seed);
      expect(a.moves, b.moves, reason: 'seed $seed');
      expect(a.score, b.score, reason: 'seed $seed');
      expect(a.bestTile, b.bestTile, reason: 'seed $seed');
      expect(a.stuck, isTrue, reason: 'seed $seed');
      expect(a.moves, lessThan(MergeBot.maxMoves), reason: 'seed $seed');
    }
  });

  test('a run scores what its merges are worth', () {
    for (var seed = 200; seed < 208; seed++) {
      final run = MergeBot.playSeed(seed: seed);
      expect(run.score, greaterThan(0), reason: 'seed $seed');
      expect(run.merges, greaterThan(0), reason: 'seed $seed');
      expect(run.bestTile, greaterThanOrEqualTo(4), reason: 'seed $seed');
      expect(run.score % 4, 0, reason: 'every merge scores a multiple of four on seed $seed');
    }
  });

  test('the run agrees with playing the same seed through the state class', () {
    const moves = [
      MergeDirection.left,
      MergeDirection.up,
      MergeDirection.left,
      MergeDirection.up,
      MergeDirection.right,
      MergeDirection.down,
    ];
    for (var seed = 300; seed < 310; seed++) {
      var state = MergeState.start(seed: seed);
      var played = 0;
      for (final d in moves) {
        final next = state.move(d);
        if (!identical(next, state)) played++;
        state = next;
      }
      final run = MergeBot.replay(seed: seed, moves: moves);
      expect(run.moves, played, reason: 'seed $seed');
      expect(run.score, state.score, reason: 'seed $seed');
      expect(run.bestTile, state.bestTile, reason: 'seed $seed');
    }
  });

  test('a replay skips a slide that would change nothing', () {
    final state = MergeState.start(seed: 4242);
    final dead = MergeDirection.values.where((d) => !MergeRules.slide(state.tiles, 4, d).changed).toList();
    if (dead.isEmpty) return;
    final run = MergeBot.replay(seed: 4242, moves: [dead.first]);
    expect(run.moves, 0);
    expect(run.bestTile, MergeRules.bestTile(state.tiles));
  });

  test('the bar rejects a run that dies early or stays small', () {
    const short = MergeRun(moves: 40, score: 300, bestTile: 512, merges: 30, stuck: true);
    const small = MergeRun(moves: 400, score: 900, bestTile: 128, merges: 200, stuck: true);
    const good = MergeRun(moves: 250, score: 3000, bestTile: 256, merges: 200, stuck: true);
    expect(MergeGenerator.accepts(short), isFalse);
    expect(MergeGenerator.accepts(small), isFalse);
    expect(MergeGenerator.accepts(good), isTrue);
  });

  test('most deals are turned down, so the bar means something', () {
    var accepted = 0;
    for (var seed = 1000; seed < 1060; seed++) {
      if (MergeGenerator.accepts(MergeBot.playSeed(seed: seed))) accepted++;
    }
    expect(accepted, greaterThan(5));
    expect(accepted, lessThan(55));
  });
}
