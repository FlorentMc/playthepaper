import 'package:playthepaper/engines/regions/regions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final tiny = RegionsGrid.parse(width: 4, height: 2, regions: tinyRegions);
  final small = RegionsGrid.parse(width: 4, height: 4, regions: smallRegions);

  test('solves the fixtures to their solutions', () {
    expect(RegionsSolver.solve(tiny, cells(tiny, tinyGivens)), cells(tiny, tinySolution));
    expect(RegionsSolver.solve(small, cells(small, smallGivens)), cells(small, smallSolution));
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, tinyGivens)), 1);
    expect(RegionsSolver.countSolutions(small, cells(small, smallGivens)), 1);
  });

  test('counts every solution up to the limit', () {
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, tinyTwoSolutionGivens), limit: 3), 2);
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, tinyTwoSolutionGivens)), 2);
    expect(RegionsSolver.countSolutions(tiny, List.filled(8, 0), limit: 1000), 96);
    expect(RegionsSolver.countSolutions(tiny, List.filled(8, 0), limit: 5), 5);
    expect(RegionsSolver.countSolutions(tiny, List.filled(8, 0), limit: 0), 0);
  });

  test('values that already break a rule have no solution', () {
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, tinyDiagonalTouch)), 0);
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, tinySideTouch)), 0);
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, '11......')), 0);
    expect(RegionsSolver.countSolutions(tiny, cells(tiny, '5.......')), 0);
    expect(RegionsSolver.countSolutions(tiny, List.filled(7, 0)), 0);
    expect(RegionsSolver.solve(tiny, cells(tiny, '1...1...')), isNull);
  });

  test('a layout with no valid filling has no solution', () {
    final dominoes = RegionsGrid.parse(width: 2, height: 2, regions: 'AABB');
    expect(RegionsSolver.countSolutions(dominoes, [0, 0, 0, 0]), 0);
    final singles = RegionsGrid.parse(width: 2, height: 2, regions: 'ABCD');
    expect(RegionsSolver.solve(singles, [0, 0, 0, 0]), isNull);
  });

  test('fill draws a random valid completion and respects its node budget', () {
    var n = 7;
    int next(int max) => (n = (n * 1103515245 + 12345) & 0x7FFFFFFF) % max;
    final filled = RegionsSolver.fill(small, List.filled(16, 0), nextInt: next);
    expect(filled, isNotNull);
    expect(small.isValidSolution(filled!), isTrue);
    final partial = List<int>.filled(16, 0)..[8] = 1;
    final again = RegionsSolver.fill(small, partial, nextInt: next);
    expect(again, isNotNull);
    expect(again![8], 1);
    expect(RegionsSolver.fill(small, List.filled(16, 0), nextInt: next, maxNodes: 0), isNull);
  });

  group('grader', () {
    test('rates the fixtures as solvable by logic', () {
      final rating = RegionsGrader.grade(small, cells(small, smallGivens));
      expect(rating.solvedByLogic, isTrue);
      expect(rating.hardest, RegionsTechnique.nakedSingle);
      expect(rating.nakedSingles + rating.hiddenSingles, 12);
      expect(RegionsGrader.grade(tiny, cells(tiny, tinyGivens)).solvedByLogic, isTrue);
    });

    test('stops when the board needs search', () {
      final rating = RegionsGrader.grade(tiny, cells(tiny, tinyTwoSolutionGivens));
      expect(rating.solvedByLogic, isFalse);
      expect(rating.hardest, RegionsTechnique.search);
      expect(RegionsGrader.grade(small, List.filled(16, 0)).solvedByLogic, isFalse);
    });

    test('uses locked candidates when singles run out', () {
      final puzzle = RegionsGenerator.generatePuzzle(seed: RegionsGenerator.seedFor('2026-09-10'));
      final rating = RegionsGrader.grade(puzzle.grid, puzzle.givens);
      expect(rating.solvedByLogic, isTrue);
      expect(rating.lockedSteps, greaterThan(0));
      expect(rating.hardest, RegionsTechnique.locked);
    });
  });
}
