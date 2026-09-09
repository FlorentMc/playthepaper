import 'dart:math';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/target/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same seed always gives the same puzzle', () {
    final a = TargetGenerator.generatePuzzle(seed: 20260910);
    final b = TargetGenerator.generatePuzzle(seed: 20260910);
    expect(a.tiles, b.tiles);
    expect(a.target, b.target);
    expect(a.solution.text, b.solution.text);
    expect(TargetGenerator().generate(DateTime.utc(2026, 9, 10)), TargetGenerator().generate(DateTime.utc(2026, 9, 10)));
  });

  test('different seeds give different puzzles', () {
    final a = TargetGenerator.generatePuzzle(seed: 1);
    final b = TargetGenerator.generatePuzzle(seed: 2);
    expect(a.tiles.join() + a.target.toString(), isNot(equals(b.tiles.join() + b.target.toString())));
  });

  test('every seed yields two distinct large tiles, four small, a reachable target that needs tiles', () {
    var preferred = 0;
    for (var seed = 100; seed < 112; seed++) {
      final puzzle = TargetGenerator.generatePuzzle(seed: seed);
      final reason = 'seed $seed';
      final large = puzzle.tiles.where(TargetPuzzle.largeTiles.contains).toList();
      expect(large.length, 2, reason: reason);
      expect(large.toSet().length, 2, reason: reason);
      final small = puzzle.tiles.where((t) => !TargetPuzzle.largeTiles.contains(t)).toList();
      expect(small.length, 4, reason: reason);
      expect(small.every((t) => t >= 1 && t <= 10), isTrue, reason: reason);
      for (final t in small.toSet()) {
        expect(small.where((x) => x == t).length, lessThanOrEqualTo(2), reason: reason);
      }
      expect(puzzle.target, inInclusiveRange(101, 999), reason: reason);
      expect(TargetExpression.evaluate(puzzle.solution.text, puzzle.tiles), puzzle.target, reason: reason);
      final min = TargetSearch(puzzle.tiles).minTiles(puzzle.target)!;
      expect(min, greaterThanOrEqualTo(TargetGenerator.minTiles), reason: reason);
      expect(puzzle.solution.numbers.length, min, reason: '$reason reveal is a shortest solution');
      if (min >= TargetGenerator.preferredMinTiles) preferred++;
    }
    expect(preferred, greaterThanOrEqualTo(9));
  });

  test('drawTiles draws from the bag without repeats beyond two', () {
    final tiles = TargetGenerator.drawTiles(Random(3));
    expect(tiles.length, 6);
    expect(tiles.take(2).toSet().length, 2);
    expect(tiles.take(2).every(TargetPuzzle.largeTiles.contains), isTrue);
    expect(tiles.skip(2).every((t) => t >= 1 && t <= 10), isTrue);
  });

  test('generate builds a record for the date that re-parses', () {
    final record = TargetGenerator().generate(DateTime.utc(2026, 10, 3));
    expect(record.id.toString(), 'target-2026-10-03-en-v1');
    expect(record.game, GameKind.target);
    expect(record.locale, 'en-GB');
    expect(record.contentVersion, 1);
    expect(record.scoringVersion, 1);
    final puzzle = TargetPuzzle.parse(record.payload, record.reveal);
    expect(puzzle.tiles.length, 6);
    expect(record.reveal['expression'], puzzle.solution.text);
  });

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(TargetGenerator.fnv1a(''), 0x811C9DC5);
    expect(TargetGenerator.fnv1a('a'), 0xE40C292C);
    expect(TargetGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(TargetGenerator.seedFor('2026-09-10'), TargetGenerator.fnv1a('target-2026-09-10'));
  });
}
