import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/regions/regions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same date always gives the same record', () {
    final a = RegionsGenerator().generate(DateTime.utc(2026, 9, 10));
    final b = RegionsGenerator().generate(DateTime.utc(2026, 9, 10));
    expect(a, b);
    expect(a.id.toString(), 'regions-2026-09-10-en-v1');
    expect(a.id.game, GameKind.regions);
    expect(a.locale, 'en-GB');
    expect(a.contentVersion, 1);
    expect(a.scoringVersion, 1);
    expect(a.payload['width'], 6);
    expect(a.payload['height'], 6);
    final local = RegionsGenerator().generate(DateTime(2026, 9, 10, 23, 30));
    expect(local.id, a.id);
    expect(local.payload, a.payload);
  });

  test('the same seed always gives the same puzzle', () {
    final a = RegionsGenerator.generatePuzzle(seed: 20260910);
    final b = RegionsGenerator.generatePuzzle(seed: 20260910);
    expect(a.toPayload(), b.toPayload());
    expect(a.toReveal(), b.toReveal());
  });

  test('different dates give different puzzles', () {
    final a = RegionsGenerator().generate(DateTime.utc(2026, 9, 10));
    final b = RegionsGenerator().generate(DateTime.utc(2026, 9, 11));
    expect(a.payload, isNot(equals(b.payload)));
  });

  test('every seed yields a valid, unique, logic-solvable 6×6 board with 8 to 14 givens', () {
    for (var seed = 100; seed < 112; seed++) {
      final reason = 'seed $seed';
      final puzzle = RegionsGenerator.generatePuzzle(seed: seed);
      expect(puzzle.width, 6, reason: reason);
      expect(puzzle.height, 6, reason: reason);
      expect(puzzle.grid.isValidSolution(puzzle.solution), isTrue, reason: reason);
      expect(RegionsSolver.countSolutions(puzzle.grid, puzzle.givens), 1, reason: reason);
      expect(RegionsSolver.solve(puzzle.grid, puzzle.givens), puzzle.solution, reason: reason);
      expect(puzzle.givenCount, inInclusiveRange(RegionsGenerator.minGivens, RegionsGenerator.maxGivens), reason: reason);
      for (final cells in puzzle.grid.regionCells) {
        expect(cells.length, inInclusiveRange(1, RegionsGrid.maxRegionSize), reason: reason);
      }
      expect(puzzle.grid.regionCells.where((c) => c.length == 1).length, lessThanOrEqualTo(1), reason: reason);
      final parsed = RegionsPuzzle.parse(puzzle.toPayload(), puzzle.toReveal());
      expect(parsed.givens, puzzle.givens, reason: reason);
      expect(parsed.solution, puzzle.solution, reason: reason);
      expect(parsed.grid.regionsString, puzzle.grid.regionsString,
          reason: '$reason: the generated board is numbered as the app reads it back');
      final rating = RegionsGrader.grade(parsed.grid, parsed.givens);
      expect(rating.solvedByLogic, isTrue, reason: reason);
      expect(rating.hiddenSingles + rating.lockedSteps, greaterThanOrEqualTo(RegionsGenerator.minReasoningSteps), reason: reason);
    }
  });

  test('partition covers the board with connected regions of 1 to 5 cells', () {
    var n = 3;
    int next(int max) => (n = (n * 1103515245 + 12345) & 0x7FFFFFFF) % max;
    var found = 0;
    for (var tries = 0; tries < 20 && found < 5; tries++) {
      final grid = RegionsGenerator.partition(6, 6, next);
      if (grid == null) continue;
      found++;
      expect(grid.cellCount, 36);
      expect(grid.regionOf.every((r) => r >= 0), isTrue);
      for (final cells in grid.regionCells) {
        expect(cells.length, inInclusiveRange(1, 5));
      }
      expect(RegionsGrid.parse(width: 6, height: 6, regions: grid.regionsString).regionsString, grid.regionsString);
    }
    expect(found, greaterThan(0));
  });

  test('carve keeps a unique solution and stops at the floor', () {
    var n = 11;
    int next(int max) => (n = (n * 1103515245 + 12345) & 0x7FFFFFFF) % max;
    RegionsGrid? grid;
    List<int>? solution;
    while (solution == null) {
      grid = RegionsGenerator.partition(6, 6, next);
      if (grid == null) continue;
      solution = RegionsSolver.fill(grid, List.filled(36, 0), nextInt: next);
    }
    final givens = RegionsGenerator.carve(grid!, solution, next, minGivens: 12);
    expect(RegionsSolver.countSolutions(grid, givens), 1);
    expect(givens.where((g) => g != 0).length, greaterThanOrEqualTo(12));
    for (var i = 0; i < 36; i++) {
      expect(givens[i] == 0 || givens[i] == solution[i], isTrue);
    }
  });

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(RegionsGenerator.fnv1a(''), 0x811C9DC5);
    expect(RegionsGenerator.fnv1a('a'), 0xE40C292C);
    expect(RegionsGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(RegionsGenerator.seedFor('2026-09-10'), RegionsGenerator.fnv1a('regions-2026-09-10'));
  });
}
