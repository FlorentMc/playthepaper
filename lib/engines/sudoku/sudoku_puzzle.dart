import 'sudoku_grid.dart';
import 'sudoku_solver.dart';

/// A validated puzzle: the givens and their unique solution.
///
/// Payload: `{"givens": "81 chars, 1-9 or 0 for blank"}`.
/// Reveal: `{"solution": "81 chars, 1-9"}`.
class SudokuPuzzle {
  /// Validates and copies [givens] and [solution]. Throws [FormatException]
  /// when the solution is not a valid grid, the givens are not a subset of
  /// it, or the givens admit more than one solution.
  factory SudokuPuzzle({required List<int> givens, required List<int> solution}) {
    if (givens.length != SudokuGrid.cellCount || solution.length != SudokuGrid.cellCount) {
      throw const FormatException('Sudoku givens and solution must have ${SudokuGrid.cellCount} cells');
    }
    if (!SudokuGrid.isValidSolution(solution)) {
      throw const FormatException('Sudoku solution is not a valid completed grid');
    }
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      final g = givens[i];
      if (g < 0 || g > 9) throw FormatException('Sudoku given at index $i is out of range: $g');
      if (g != 0 && g != solution[i]) {
        throw FormatException('Sudoku given at index $i ($g) disagrees with the solution (${solution[i]})');
      }
    }
    if (SudokuSolver.countSolutions(givens) != 1) {
      throw const FormatException('Sudoku givens do not have a unique solution');
    }
    return SudokuPuzzle._(
      List<int>.unmodifiable(givens),
      List<int>.unmodifiable(solution),
    );
  }

  const SudokuPuzzle._(this.givens, this.solution);

  static SudokuPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawGivens = payload['givens'];
    if (rawGivens is! String) throw const FormatException('Sudoku payload is missing "givens"');
    final rawSolution = reveal['solution'];
    if (rawSolution is! String) throw const FormatException('Sudoku reveal is missing "solution"');
    return SudokuPuzzle(
      givens: SudokuGrid.parseCells(rawGivens, field: 'givens', allowBlank: true),
      solution: SudokuGrid.parseCells(rawSolution, field: 'solution', allowBlank: false),
    );
  }

  /// 81 values, 0 for a blank cell.
  final List<int> givens;

  /// 81 values, 1–9.
  final List<int> solution;

  bool isGiven(int index) => givens[index] != 0;

  int get givenCount => givens.where((g) => g != 0).length;

  String get givensString => SudokuGrid.formatCells(givens);
  String get solutionString => SudokuGrid.formatCells(solution);

  Map<String, dynamic> toPayload() => {'givens': givensString};
  Map<String, dynamic> toReveal() => {'solution': solutionString};
}
