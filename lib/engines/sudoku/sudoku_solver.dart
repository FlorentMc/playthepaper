import 'sudoku_grid.dart';

/// Backtracking solver over bitmask candidate sets, always branching on the
/// cell with the fewest candidates.
class SudokuSolver {
  SudokuSolver._();

  /// The number of solutions, capped at [limit]. A grid whose filled cells
  /// already break a rule has none.
  static int countSolutions(List<int> grid, {int limit = 2}) {
    if (limit <= 0) return 0;
    final search = _Search(grid);
    if (!search.consistent) return 0;
    return search.count(limit, captureFirst: false);
  }

  /// The first solution found, or null when there is none.
  static List<int>? solve(List<int> grid) {
    final search = _Search(grid);
    if (!search.consistent) return null;
    search.count(1, captureFirst: true);
    return search.solution;
  }
}

class _Search {
  _Search(List<int> grid) : cells = List<int>.of(grid, growable: false) {
    if (cells.length != SudokuGrid.cellCount) {
      consistent = false;
      return;
    }
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      final v = cells[i];
      if (v == 0) continue;
      if (v < 1 || v > 9 || _used(i) & SudokuGrid.bit(v) != 0) {
        consistent = false;
        return;
      }
      _place(i, v);
    }
  }

  final List<int> cells;
  final List<int> _rowMask = List.filled(9, 0);
  final List<int> _colMask = List.filled(9, 0);
  final List<int> _boxMask = List.filled(9, 0);
  bool consistent = true;
  List<int>? solution;

  int _used(int i) => _rowMask[SudokuGrid.rowOf[i]] | _colMask[SudokuGrid.colOf[i]] | _boxMask[SudokuGrid.boxOf[i]];

  void _place(int i, int d) {
    final b = SudokuGrid.bit(d);
    cells[i] = d;
    _rowMask[SudokuGrid.rowOf[i]] |= b;
    _colMask[SudokuGrid.colOf[i]] |= b;
    _boxMask[SudokuGrid.boxOf[i]] |= b;
  }

  void _unplace(int i, int d) {
    final b = SudokuGrid.bit(d);
    cells[i] = 0;
    _rowMask[SudokuGrid.rowOf[i]] &= ~b;
    _colMask[SudokuGrid.colOf[i]] &= ~b;
    _boxMask[SudokuGrid.boxOf[i]] &= ~b;
  }

  int count(int limit, {required bool captureFirst}) {
    var best = -1;
    var bestMask = 0;
    var bestCount = 10;
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      if (cells[i] != 0) continue;
      final mask = ~_used(i) & SudokuGrid.allDigits;
      final n = SudokuGrid.bitCount(mask);
      if (n == 0) return 0;
      if (n < bestCount) {
        best = i;
        bestMask = mask;
        bestCount = n;
        if (n == 1) break;
      }
    }
    if (best == -1) {
      if (captureFirst && solution == null) solution = List<int>.of(cells, growable: false);
      return 1;
    }
    var total = 0;
    var mask = bestMask;
    while (mask != 0) {
      final low = mask & -mask;
      mask ^= low;
      final d = low.bitLength - 1;
      _place(best, d);
      total += count(limit - total, captureFirst: captureFirst);
      _unplace(best, d);
      if (total >= limit) return total;
    }
    return total;
  }
}
