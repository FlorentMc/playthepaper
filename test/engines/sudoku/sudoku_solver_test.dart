import 'package:playthepaper/engines/sudoku/sudoku.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final solution = cells(singlesOnlySolution, allowBlank: false);

  test('a proper puzzle has exactly one solution and solve finds it', () {
    final givens = cells(singlesOnlyGivens);
    expect(SudokuSolver.countSolutions(givens), 1);
    expect(SudokuSolver.countSolutions(givens, limit: 10), 1);
    expect(SudokuSolver.solve(givens), solution);
    expect(SudokuGrid.isValidSolution(SudokuSolver.solve(givens)!), isTrue);
  });

  test('a solved grid counts as one solution', () {
    expect(SudokuSolver.countSolutions(solution), 1);
    expect(SudokuSolver.solve(solution), solution);
  });

  test('blanking one row keeps the solution unique', () {
    final grid = List<int>.of(solution);
    for (var c = 0; c < 9; c++) {
      grid[4 * 9 + c] = 0;
    }
    expect(SudokuSolver.countSolutions(grid), 1);
  });

  test('blanking two rows of a band admits several solutions', () {
    final grid = twoSolutionGrid(solution);
    expect(SudokuSolver.countSolutions(grid), 2);
    expect(SudokuSolver.countSolutions(grid, limit: 1), 1);
    expect(SudokuSolver.countSolutions(grid, limit: 1000), greaterThanOrEqualTo(2));
    final found = SudokuSolver.solve(grid)!;
    expect(SudokuGrid.isValidSolution(found), isTrue);
    for (var i = 18; i < 81; i++) {
      expect(found[i], solution[i]);
    }
  });

  test('the empty grid hits the limit', () {
    final empty = List<int>.filled(81, 0);
    expect(SudokuSolver.countSolutions(empty, limit: 5), 5);
    expect(SudokuGrid.isValidSolution(SudokuSolver.solve(empty)!), isTrue);
  });

  test('contradictory or malformed grids have no solution', () {
    final clash = cells(singlesOnlyGivens);
    clash[2] = 5;
    expect(SudokuSolver.countSolutions(clash), 0);
    expect(SudokuSolver.solve(clash), isNull);
    expect(SudokuSolver.countSolutions(List<int>.filled(80, 0)), 0);
    final bad = List<int>.filled(81, 0);
    bad[0] = 10;
    expect(SudokuSolver.countSolutions(bad), 0);
    expect(SudokuSolver.countSolutions(cells(singlesOnlyGivens), limit: 0), 0);
  });

  test('grid geometry is consistent', () {
    for (var i = 0; i < 81; i++) {
      expect(SudokuGrid.peers[i].length, 20);
      expect(SudokuGrid.peers[i], isNot(contains(i)));
      expect(SudokuGrid.rows[SudokuGrid.rowOf[i]], contains(i));
      expect(SudokuGrid.cols[SudokuGrid.colOf[i]], contains(i));
      expect(SudokuGrid.boxes[SudokuGrid.boxOf[i]], contains(i));
    }
    expect(SudokuGrid.units.length, 27);
    expect(SudokuGrid.boxOf[40], 4);
    expect(SudokuGrid.boxOf[80], 8);
    expect(SudokuGrid.bitCount(SudokuGrid.allDigits), 9);
    expect(SudokuGrid.lowestDigit(SudokuGrid.bit(7) | SudokuGrid.bit(9)), 7);
    expect(SudokuGrid.digitsOf(SudokuGrid.bit(1) | SudokuGrid.bit(4)).toList(), [1, 4]);
  });
}
