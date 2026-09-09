import 'nonogram_line.dart';
import 'nonogram_puzzle.dart';

/// What the solver learned about a set of clues, independently of any
/// picture: how many solutions exist (counted up to two) and whether row and
/// column deduction alone finds the picture, without guessing.
class NonogramAnalysis {
  const NonogramAnalysis({required this.solutions, required this.lineSolvable, required this.sweeps});

  /// 0, 1 or 2 (meaning two or more).
  final int solutions;

  /// True when alternating row and column deductions decide every cell.
  final bool lineSolvable;

  /// Sweeps over all rows and columns that the line solver needed, each one
  /// deciding at least one cell; 0 when it could not finish on its own.
  final int sweeps;

  bool get isUnique => solutions == 1;
}

/// Solves clues by line deduction with a depth-first search on top. Works
/// from the clues only, so it proves uniqueness rather than assuming it.
class NonogramSolver {
  NonogramSolver._(this.width, this.height, this.rows, this.cols)
      : rowFilled = List<int>.filled(height, 0),
        rowEmpty = List<int>.filled(height, 0);

  final int width;
  final int height;
  final List<List<int>> rows;
  final List<List<int>> cols;
  final List<int> rowFilled;
  final List<int> rowEmpty;

  /// Counts the solutions of [puzzle]'s clues, stopping at [limit].
  static int countSolutions(NonogramPuzzle puzzle, {int limit = 2}) =>
      countSolutionsOf(width: puzzle.width, height: puzzle.height, rows: puzzle.rows, cols: puzzle.cols, limit: limit);

  static int countSolutionsOf({
    required int width,
    required int height,
    required List<List<int>> rows,
    required List<List<int>> cols,
    int limit = 2,
  }) {
    final solver = NonogramSolver._(width, height, rows, cols);
    return solver._search(limit, null);
  }

  /// The picture the clues describe, as row masks, or null unless exactly
  /// one exists.
  static List<int>? solve({
    required int width,
    required int height,
    required List<List<int>> rows,
    required List<List<int>> cols,
  }) {
    final solver = NonogramSolver._(width, height, rows, cols);
    final found = <List<int>>[];
    if (solver._search(2, found) != 1) return null;
    return found.single;
  }

  static NonogramAnalysis analyse(NonogramPuzzle puzzle) =>
      analyseClues(width: puzzle.width, height: puzzle.height, rows: puzzle.rows, cols: puzzle.cols);

  static NonogramAnalysis analyseClues({
    required int width,
    required int height,
    required List<List<int>> rows,
    required List<List<int>> cols,
  }) {
    final solutions = countSolutionsOf(width: width, height: height, rows: rows, cols: cols);
    final solver = NonogramSolver._(width, height, rows, cols);
    final sweeps = solver._propagate();
    final complete = sweeps >= 0 && solver._isComplete;
    return NonogramAnalysis(solutions: solutions, lineSolvable: complete, sweeps: complete ? sweeps : 0);
  }

  bool get _isComplete {
    final all = (1 << width) - 1;
    for (var r = 0; r < height; r++) {
      if (rowFilled[r] | rowEmpty[r] != all) return false;
    }
    return true;
  }

  int _colFilled(int c) {
    var mask = 0;
    for (var r = 0; r < height; r++) {
      if (rowFilled[r] & (1 << c) != 0) mask |= 1 << r;
    }
    return mask;
  }

  int _colEmpty(int c) {
    var mask = 0;
    for (var r = 0; r < height; r++) {
      if (rowEmpty[r] & (1 << c) != 0) mask |= 1 << r;
    }
    return mask;
  }

  /// Runs row and column deductions until nothing changes. Returns the number
  /// of sweeps that decided a cell, or -1 on a contradiction.
  int _propagate() {
    var sweeps = 0;
    while (true) {
      var changed = false;
      for (var r = 0; r < height; r++) {
        final d = NonogramLine.deduce(length: width, clues: rows[r], knownFilled: rowFilled[r], knownEmpty: rowEmpty[r]);
        if (d.isContradiction) return -1;
        if (d.filled & ~rowFilled[r] != 0 || d.empty & ~rowEmpty[r] != 0) {
          rowFilled[r] |= d.filled;
          rowEmpty[r] |= d.empty;
          changed = true;
        }
      }
      for (var c = 0; c < width; c++) {
        final d = NonogramLine.deduce(length: height, clues: cols[c], knownFilled: _colFilled(c), knownEmpty: _colEmpty(c));
        if (d.isContradiction) return -1;
        for (var r = 0; r < height; r++) {
          final bit = 1 << r;
          if (d.filled & bit != 0 && rowFilled[r] & (1 << c) == 0) {
            rowFilled[r] |= 1 << c;
            changed = true;
          }
          if (d.empty & bit != 0 && rowEmpty[r] & (1 << c) == 0) {
            rowEmpty[r] |= 1 << c;
            changed = true;
          }
        }
      }
      if (!changed) return sweeps;
      sweeps++;
    }
  }

  int _search(int limit, List<List<int>>? found) {
    if (_propagate() < 0) return 0;
    if (_isComplete) {
      found?.add(List<int>.of(rowFilled));
      return 1;
    }
    var r = 0, c = 0;
    outer:
    for (r = 0; r < height; r++) {
      for (c = 0; c < width; c++) {
        if ((rowFilled[r] | rowEmpty[r]) & (1 << c) == 0) break outer;
      }
    }
    final savedFilled = List<int>.of(rowFilled);
    final savedEmpty = List<int>.of(rowEmpty);
    var total = 0;
    for (final fill in [true, false]) {
      if (fill) {
        rowFilled[r] |= 1 << c;
      } else {
        rowEmpty[r] |= 1 << c;
      }
      total += _search(limit - total, found);
      rowFilled.setAll(0, savedFilled);
      rowEmpty.setAll(0, savedEmpty);
      if (total >= limit) return total;
    }
    return total;
  }
}
