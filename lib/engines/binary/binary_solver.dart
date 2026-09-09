import 'binary_rules.dart';

/// Rule propagation plus backtracking. Propagation applies the deductions a
/// player makes by hand: a pair or a gap forces the third cell, a line with
/// half its symbols placed fills the rest with the other, and a line two
/// cells short of copying a finished line takes the other way round.
class BinarySolver {
  BinarySolver._();

  /// The number of solutions, capped at [limit]. A grid that already breaks
  /// a rule has none.
  static int countSolutions(List<int> grid, int size, {int limit = 2}) {
    if (limit <= 0) return 0;
    final start = propagate(grid, size);
    if (start == null) return 0;
    return _count(start, size, limit, null);
  }

  /// The first solution found, or null when there is none.
  static List<int>? solve(List<int> grid, int size) {
    final start = propagate(grid, size);
    if (start == null) return null;
    final out = <List<int>>[];
    _count(start, size, 1, out);
    return out.isEmpty ? null : out.first;
  }

  /// True when propagation alone completes the grid. With [basicOnly] only
  /// the pair-and-gap deduction is used, which marks the puzzles too easy
  /// to publish.
  static bool solvesByPropagation(List<int> grid, int size, {bool basicOnly = false}) {
    final result = propagate(grid, size, basicOnly: basicOnly);
    return result != null && BinaryRules.isComplete(result);
  }

  /// Applies every forced deduction until nothing changes. Returns the
  /// filled copy, or null when the grid contradicts a rule.
  static List<int>? propagate(List<int> grid, int size, {bool basicOnly = false}) {
    if (grid.length != size * size) return null;
    final cells = List<int>.of(grid, growable: false);
    final half = size ~/ 2;
    final lines = BinaryRules.lines(size);
    var changed = true;
    while (changed) {
      changed = false;
      for (var li = 0; li < lines.length; li++) {
        final line = lines[li];
        var zeros = 0, ones = 0;
        for (final i in line) {
          final v = cells[i];
          if (v == 0) {
            zeros++;
          } else if (v == 1) {
            ones++;
          }
        }
        if (zeros > half || ones > half) return null;
        for (var k = 0; k + 2 < size; k++) {
          final a = cells[line[k]], b = cells[line[k + 1]], c = cells[line[k + 2]];
          if (a != BinaryRules.empty && a == b && b == c) return null;
          if (a != BinaryRules.empty && a == b && c == BinaryRules.empty) {
            cells[line[k + 2]] = 1 - a;
            changed = true;
          } else if (b != BinaryRules.empty && b == c && a == BinaryRules.empty) {
            cells[line[k]] = 1 - b;
            changed = true;
          } else if (a != BinaryRules.empty && a == c && b == BinaryRules.empty) {
            cells[line[k + 1]] = 1 - a;
            changed = true;
          }
        }
        if (basicOnly) continue;
        if (zeros + ones < size && (zeros == half || ones == half)) {
          final fill = zeros == half ? 1 : 0;
          for (final i in line) {
            if (cells[i] == BinaryRules.empty) {
              cells[i] = fill;
              changed = true;
            }
          }
          continue;
        }
        final empties = line.where((i) => cells[i] == BinaryRules.empty).length;
        if (empties != 0 && empties != 2) continue;
        final groupStart = li < size ? 0 : size;
        for (var lj = groupStart; lj < groupStart + size; lj++) {
          if (lj == li) continue;
          final other = lines[lj];
          if (!_matchesFilled(cells, line, other)) continue;
          if (empties == 0) return null;
          for (var k = 0; k < size; k++) {
            if (cells[line[k]] == BinaryRules.empty) cells[line[k]] = 1 - cells[other[k]];
          }
          changed = true;
          break;
        }
      }
    }
    return cells;
  }

  /// True when [other] is complete and agrees with [line] on every filled cell.
  static bool _matchesFilled(List<int> cells, List<int> line, List<int> other) {
    for (var k = 0; k < line.length; k++) {
      final o = cells[other[k]];
      if (o == BinaryRules.empty) return false;
      final v = cells[line[k]];
      if (v != BinaryRules.empty && v != o) return false;
    }
    return true;
  }

  static int _count(List<int> cells, int size, int limit, List<List<int>>? capture) {
    final pick = _mostConstrained(cells, size);
    if (pick == -1) {
      if (!BinaryRules.isValidSolution(cells, size)) return 0;
      capture?.add(cells);
      return 1;
    }
    var total = 0;
    for (final v in const [0, 1]) {
      final next = List<int>.of(cells, growable: false);
      next[pick] = v;
      final propagated = propagate(next, size);
      if (propagated == null) continue;
      total += _count(propagated, size, limit - total, capture);
      if (total >= limit) return total;
    }
    return total;
  }

  /// An empty cell in the line with the fewest empties, or -1 when full.
  static int _mostConstrained(List<int> cells, int size) {
    var best = -1;
    var bestEmpties = size + 1;
    for (final line in BinaryRules.lines(size)) {
      var empties = 0;
      var first = -1;
      for (final i in line) {
        if (cells[i] == BinaryRules.empty) {
          empties++;
          if (first == -1) first = i;
        }
      }
      if (empties > 0 && empties < bestEmpties) {
        bestEmpties = empties;
        best = first;
      }
    }
    return best;
  }
}
