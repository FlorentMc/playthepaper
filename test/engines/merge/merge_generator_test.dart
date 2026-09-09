import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/merge/merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same date always deals the same game', () {
    final a = MergeGenerator().generate(DateTime.utc(2026, 9, 10));
    final b = MergeGenerator().generate(DateTime.utc(2026, 9, 10));
    expect(a, b);
    expect(a.payload['seed'], b.payload['seed']);
    expect(
      MergePuzzle.parse(a.payload, a.reveal).openingTiles,
      MergePuzzle.parse(b.payload, b.reveal).openingTiles,
    );
  });

  test('different dates deal different games', () {
    final a = MergeGenerator().generate(DateTime.utc(2026, 9, 10));
    final b = MergeGenerator().generate(DateTime.utc(2026, 9, 11));
    expect(a.payload['seed'], isNot(b.payload['seed']));
  });

  test('generate builds a record for the date that re-parses', () {
    final record = MergeGenerator().generate(DateTime.utc(2026, 10, 3));
    expect(record.id.toString(), 'merge-2026-10-03-en-v1');
    expect(record.game, GameKind.merge);
    expect(record.locale, 'en-GB');
    expect(record.contentVersion, 1);
    expect(record.scoringVersion, 1);
    expect(record.reveal, isEmpty);
    expect(record.payload['size'], 4);
    final puzzle = MergePuzzle.parse(record.payload, record.reveal);
    expect(puzzle.size, 4);
    expect(puzzle.openingTiles.where((v) => v != 0).length, 2);
  });

  test('every deal clears the bar the reference player sets', () {
    for (var seed = 500; seed < 515; seed++) {
      final puzzle = MergeGenerator.generatePuzzle(seed: seed);
      final run = MergeBot.play(puzzle);
      final reason = 'seed $seed';
      expect(puzzle.seed, inInclusiveRange(1, 0xFFFFFFFF), reason: reason);
      expect(puzzle.size, 4, reason: reason);
      expect(MergeGenerator.accepts(run), isTrue, reason: reason);
      expect(run.moves, greaterThanOrEqualTo(MergeGenerator.minMoves), reason: reason);
      expect(run.bestTile, greaterThanOrEqualTo(MergeGenerator.minBestTile), reason: reason);
      expect(MergeRules.hasMove(puzzle.openingTiles, 4), isTrue, reason: reason);
    }
  });

  test('a run of dates all pass and none takes long', () {
    final clock = Stopwatch()..start();
    final seeds = <int>{};
    for (var day = 10; day <= 30; day++) {
      final record = MergeGenerator().generate(DateTime.utc(2026, 9, day));
      final puzzle = MergePuzzle.parse(record.payload, record.reveal);
      expect(MergeGenerator.accepts(MergeBot.play(puzzle)), isTrue, reason: 'day $day');
      seeds.add(puzzle.seed);
    }
    expect(seeds.length, 21, reason: 'every date gets its own deal');
    expect(clock.elapsedMilliseconds, lessThan(21 * 2000));
  });

  test('the seed for a date is stable', () {
    expect(MergeGenerator.seedFor('2026-09-10'), MergeGenerator.seedFor('2026-09-10'));
    expect(MergeGenerator.seedFor('2026-09-10'), isNot(MergeGenerator.seedFor('2026-09-11')));
    expect(MergeGenerator.fnv1a('merge-2026-09-10'), 3476233214);
  });
}
