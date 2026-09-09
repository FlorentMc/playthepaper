import 'dart:math';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/loop/loop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final generator = LoopGenerator();

  test('the same date always gives the same puzzle', () {
    final a = generator.generate(DateTime.utc(2026, 9, 10));
    final b = LoopGenerator().generate(DateTime.utc(2026, 9, 10));
    expect(a, b);
    expect(a.id.toString(), 'loop-2026-09-10-en-v1');
    expect(a.id.game, GameKind.loop);
    expect(a.locale, 'en-GB');
    expect(a.contentVersion, 1);
    expect(a.scoringVersion, 1);
    expect(a.payload['width'], 6);
    expect(a.payload['height'], 6);
    expect(LoopGenerator.generatePuzzle(LoopGenerator.seedFor('2026-09-10')).cluesString, a.payload['clues']);
  });

  test('different dates give different puzzles', () {
    final a = generator.generate(DateTime.utc(2026, 9, 10));
    final b = generator.generate(DateTime.utc(2026, 9, 11));
    expect(a.payload, isNot(equals(b.payload)));
  });

  test('a run of dates yields valid, unique, fair puzzles within the clue and step bounds', () {
    for (var day = 0; day < 12; day++) {
      final date = DateTime.utc(2026, 10, 1 + day);
      final record = generator.generate(date);
      final reason = record.id.toString();
      final puzzle = LoopPuzzle.parse(record.payload, record.reveal);
      expect(puzzle.width, LoopGenerator.width, reason: reason);
      expect(puzzle.height, LoopGenerator.height, reason: reason);
      expect(LoopRules.isSolved(puzzle.grid, puzzle.clues, puzzle.solution), isTrue, reason: reason);
      expect(LoopSolver.countSolutions(puzzle.grid, puzzle.clues), 1, reason: reason);
      expect(LoopSolver.solve(puzzle.grid, puzzle.clues), puzzle.solution, reason: reason);
      expect(puzzle.clueCount, inInclusiveRange(LoopGenerator.minClues, LoopGenerator.maxClues), reason: reason);
      expect(puzzle.lineCount, greaterThanOrEqualTo(LoopGenerator.minLoopLength), reason: reason);
      expect(LoopSolver.tier(puzzle.grid, puzzle.clues), LoopTier.fair, reason: reason);
      final deduced = LoopSolver.deduce(puzzle.grid, puzzle.clues, List.filled(puzzle.grid.edgeCount, LoopSolver.unknown))!;
      expect(deduced.steps, inInclusiveRange(LoopGenerator.minSteps, LoopGenerator.maxSteps), reason: reason);
      expect(puzzle.clues.contains(4), isFalse, reason: reason);
    }
  });

  test('a grown region has a simple boundary and full clues match it', () {
    final grid = LoopGrid(6, 6);
    for (var seed = 0; seed < 20; seed++) {
      final region = LoopGenerator.growRegion(grid, Random(seed), 18);
      final lines = LoopGenerator.boundary(grid, region);
      final clues = LoopGenerator.fullClues(grid, lines);
      expect(LoopRules.violation(grid, clues, lines), isNull, reason: 'seed $seed');
      expect(region.where((r) => r).length, inInclusiveRange(1, 18), reason: 'seed $seed');
      for (var cell = 0; cell < grid.cellCount; cell++) {
        final n = LoopRules.lineCount(grid.cellEdges[cell], lines);
        expect(clues[cell], n > 3 ? -1 : n, reason: 'seed $seed cell $cell');
      }
    }
  });

  test('carving keeps the puzzle within one-step reasoning', () {
    final grid = LoopGrid(6, 6);
    final random = Random(5);
    final region = LoopGenerator.growRegion(grid, random, 18);
    final lines = LoopGenerator.boundary(grid, region);
    final full = LoopGenerator.fullClues(grid, lines);
    final carved = LoopGenerator.carve(grid, full, random, target: 10);
    final kept = carved.where((c) => c >= 0).length;
    expect(kept, lessThan(full.where((c) => c >= 0).length));
    expect(kept, greaterThanOrEqualTo(10));
    for (var cell = 0; cell < grid.cellCount; cell++) {
      expect(carved[cell] == -1 || carved[cell] == full[cell], isTrue);
    }
    final deduced = LoopSolver.deduce(grid, carved, List.filled(grid.edgeCount, LoopSolver.unknown))!;
    expect(deduced.complete, isTrue);
    expect(deduced.steps, lessThanOrEqualTo(LoopGenerator.maxSteps));
    expect(LoopSolver.countSolutions(grid, carved), 1);
  });

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(LoopGenerator.fnv1a(''), 0x811C9DC5);
    expect(LoopGenerator.fnv1a('a'), 0xE40C292C);
    expect(LoopGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(LoopGenerator.seedFor('2026-09-10'), LoopGenerator.fnv1a('loop-2026-09-10'));
  });
}
