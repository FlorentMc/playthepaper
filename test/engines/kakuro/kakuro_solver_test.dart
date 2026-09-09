import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('combinations enumerate the digit sets for a length and sum', () {
    expect(KakuroSolver.combinations(2, 3), [KakuroGrid.bit(1) | KakuroGrid.bit(2)]);
    expect(KakuroSolver.combinations(2, 17), [KakuroGrid.bit(8) | KakuroGrid.bit(9)]);
    expect(KakuroSolver.combinations(2, 4), [KakuroGrid.bit(1) | KakuroGrid.bit(3)], reason: '2+2 repeats');
    expect(KakuroSolver.combinations(3, 6), [KakuroGrid.bit(1) | KakuroGrid.bit(2) | KakuroGrid.bit(3)]);
    expect(KakuroSolver.combinations(2, 10).length, 4);
    expect(KakuroSolver.combinations(4, 20).length, 12);
    expect(KakuroSolver.combinations(9, 45).length, 1);
    expect(KakuroSolver.combinations(2, 18), isEmpty);
    expect(KakuroSolver.combinations(3, 5), isEmpty);
    expect(KakuroSolver.combinations(10, 45), isEmpty);
    for (final combo in KakuroSolver.combinations(3, 15)) {
      expect(KakuroGrid.bitCount(combo), 3);
      expect(KakuroGrid.digitsOf(combo).reduce((a, b) => a + b), 15);
    }
  });

  test('a proper puzzle has exactly one solution and solve finds it', () {
    final grid = gridOf(smallPayload());
    expect(KakuroSolver.countSolutions(grid), 1);
    expect(KakuroSolver.countSolutions(grid, limit: 10), 1);
    expect(KakuroSolver.solve(grid), [0, 0, 0, 0, 1, 2, 0, 3, 1]);
  });

  test('a board with two solutions counts two', () {
    final grid = gridOf(twoSolutionPayload());
    expect(KakuroSolver.countSolutions(grid), 2);
    expect(KakuroSolver.countSolutions(grid, limit: 1), 1);
    expect(KakuroSolver.countSolutions(grid, limit: 100), 2);
    expect(KakuroSolver.countSolutions(grid, limit: 0), 0);
    final found = KakuroSolver.solve(grid)!;
    expect(grid.isSolvedBy(found), isTrue);
  });

  test('contradictory clues have no solution', () {
    final grid = gridOf(impossiblePayload());
    expect(KakuroSolver.countSolutions(grid), 0);
    expect(KakuroSolver.solve(grid), isNull);
    expect(KakuroSolver.deduce(grid).consistent, isFalse);
  });

  test('a solution never repeats a digit in a run', () {
    final grid = gridOf(repeatPayload());
    final found = KakuroSolver.solve(grid)!;
    expect(grid.firstViolation(found), isNull);
    expect(found, [0, 0, 0, 0, 3, 1, 0, 1, 5]);
    expect(KakuroSolver.countSolutions(grid, limit: 10), 1);
  });

  test('deduction alone settles the small board', () {
    final grid = gridOf(smallPayload());
    final deduction = KakuroSolver.deduce(grid);
    expect(deduction.consistent, isTrue);
    expect(deduction.solves(grid), isTrue);
    expect(deduction.fixedCount(grid), 4);
    expect(deduction.candidates[4], KakuroGrid.bit(1));
    expect(deduction.candidates[8], KakuroGrid.bit(1));
    expect(deduction.candidates[0], 0);
    expect(deduction.rounds, greaterThanOrEqualTo(1));
  });

  test('deduction leaves an ambiguous board open', () {
    final grid = gridOf(twoSolutionPayload());
    final deduction = KakuroSolver.deduce(grid);
    expect(deduction.consistent, isTrue);
    expect(deduction.solves(grid), isFalse);
    expect(deduction.fixedCount(grid), 0);
    expect(deduction.candidates[4], KakuroGrid.bit(1) | KakuroGrid.bit(2));
  });

  test('a generated board is solved and unique, and the solver agrees with the reveal', () {
    final puzzle = KakuroGenerator.generatePuzzle(7);
    expect(KakuroSolver.countSolutions(puzzle.grid), 1);
    expect(KakuroSolver.solve(puzzle.grid), puzzle.solution);
    expect(KakuroSolver.deduce(puzzle.grid).solves(puzzle.grid), isTrue);
  });
}
