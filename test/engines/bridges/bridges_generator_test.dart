import 'dart:math';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same date always gives the same puzzle', () {
    final date = DateTime.utc(2026, 9, 10);
    final a = BridgesGenerator().generate(date);
    final b = BridgesGenerator().generate(date);
    expect(a.toJson(), b.toJson());
    expect(a.id.toString(), 'bridges-2026-09-10-en-v1');
    expect(a.id.game, GameKind.bridges);
    expect(a.locale, 'en-GB');
    expect(a.contentVersion, 1);
    expect(a.scoringVersion, 1);
  });

  test('different dates give different puzzles', () {
    final a = BridgesGenerator().generate(DateTime.utc(2026, 9, 10));
    final b = BridgesGenerator().generate(DateTime.utc(2026, 9, 11));
    expect(a.payload, isNot(equals(b.payload)));
  });

  test('every seed yields a unique, medium-rated 7×7 puzzle with 12 to 16 islands', () {
    for (var seed = 100; seed < 112; seed++) {
      final puzzle = BridgesGenerator.generatePuzzle(seed: seed);
      final reason = 'seed $seed';
      final layout = puzzle.layout;
      expect(layout.width, 7, reason: reason);
      expect(layout.height, 7, reason: reason);
      expect(puzzle.islandCount, inInclusiveRange(BridgesGenerator.minIslands, BridgesGenerator.maxIslands), reason: reason);
      expect(BridgesSolver.countSolutions(layout), 1, reason: reason);
      expect(BridgesSolver.solve(layout), puzzle.solution, reason: reason);
      expect(BridgesSolver.rate(layout), BridgesRating.medium, reason: reason);
      expect(layout.isSolution(puzzle.solution), isTrue, reason: reason);
      for (final a in layout.islands) {
        for (final b in layout.islands) {
          if (identical(a, b)) continue;
          expect((a.row - b.row).abs() + (a.col - b.col).abs(), greaterThan(1), reason: '$reason: islands touch');
        }
      }
      final parsed = BridgesPuzzle.parse(puzzle.toPayload(), puzzle.toReveal());
      expect(parsed.solution, puzzle.solution, reason: reason);
    }
  });

  test('generated records parse through the engine', () {
    for (var d = 0; d < 10; d++) {
      final record = BridgesGenerator().generate(DateTime.utc(2026, 10, 1 + d));
      final puzzle = BridgesPuzzle.parse(record.payload, record.reveal);
      expect(puzzle.islandCount, inInclusiveRange(12, 16));
      expect(puzzle.toReveal(), record.reveal);
    }
  });

  test('grown boards are always consistent with their own bridges', () {
    var grown = 0;
    for (var seed = 0; seed < 40; seed++) {
      final board = BridgesGenerator.grow(Random(seed), width: 7, height: 7, minIslands: 10, maxIslands: 16);
      if (board == null) continue;
      grown++;
      final layout = BridgesLayout(width: 7, height: 7, islands: board.islands);
      final solution = board.solutionFor(layout);
      expect(layout.firstFault(solution), isNull, reason: 'seed $seed');
    }
    expect(grown, greaterThan(10));
  });

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(BridgesGenerator.fnv1a(''), 0x811C9DC5);
    expect(BridgesGenerator.fnv1a('a'), 0xE40C292C);
    expect(BridgesGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(BridgesGenerator.seedFor('2026-09-10'), BridgesGenerator.fnv1a('bridges-2026-09-10'));
  });
}
