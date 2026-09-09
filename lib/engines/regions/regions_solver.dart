import 'regions_grid.dart';

/// Backtracking solver over bitmask candidate sets. Placing a digit removes
/// it from every touching cell and every cell of the same region; naked and
/// hidden singles are propagated before each branch, which is on the cell
/// with the fewest candidates.
class RegionsSolver {
  RegionsSolver._();

  /// The number of solutions completing [values] on [grid], capped at
  /// [limit]. Values that already break a rule have none.
  static int countSolutions(RegionsGrid grid, List<int> values, {int limit = 2}) {
    if (limit <= 0) return 0;
    final search = _Search(grid, values);
    if (!search.consistent) return 0;
    return search.count(limit, captureFirst: false);
  }

  /// The first solution found, or null when there is none.
  static List<int>? solve(RegionsGrid grid, List<int> values) {
    final search = _Search(grid, values);
    if (!search.consistent) return null;
    search.count(1, captureFirst: true);
    return search.solution;
  }

  /// A solution found by trying digits in an order drawn from [nextInt],
  /// or null when there is none or the search exceeds [maxNodes] branches.
  static List<int>? fill(
    RegionsGrid grid,
    List<int> values, {
    required int Function(int max) nextInt,
    int maxNodes = 20000,
  }) {
    final search = _Search(grid, values, nextInt: nextInt, maxNodes: maxNodes);
    if (!search.consistent) return null;
    search.count(1, captureFirst: true);
    return search.exhausted ? null : search.solution;
  }
}

class _Search {
  _Search(this.grid, List<int> start, {this.nextInt, this.maxNodes = -1}) {
    final n = grid.cellCount;
    if (start.length != n) {
      consistent = false;
      return;
    }
    values = List<int>.of(start, growable: false);
    cand = List<int>.generate(n, (i) => RegionsGrid.digitsUpTo(grid.sizeOf(i)), growable: false);
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == 0) continue;
      if (v < 1 || v > grid.sizeOf(i) || cand[i] & RegionsGrid.bit(v) == 0) {
        consistent = false;
        return;
      }
      if (!_place(values, cand, i, v)) {
        consistent = false;
        return;
      }
    }
    consistent = _propagate(values, cand);
  }

  final RegionsGrid grid;
  final int Function(int max)? nextInt;
  final int maxNodes;
  late List<int> values;
  late List<int> cand;
  bool consistent = true;
  bool exhausted = false;
  int nodes = 0;
  List<int>? solution;

  /// Writes [d] into [i] and removes it from the cells that constrain [i].
  /// False when some blank cell is left with no candidate.
  bool _place(List<int> values, List<int> cand, int i, int d) {
    final b = RegionsGrid.bit(d);
    values[i] = d;
    cand[i] = b;
    for (final j in grid.neighbours[i]) {
      if (values[j] == d) return false;
      if (values[j] == 0 && (cand[j] &= ~b) == 0) return false;
    }
    for (final j in grid.regionCells[grid.regionOf[i]]) {
      if (j == i) continue;
      if (values[j] == d) return false;
      if (values[j] == 0 && (cand[j] &= ~b) == 0) return false;
    }
    return true;
  }

  bool _propagate(List<int> values, List<int> cand) {
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < values.length; i++) {
        if (values[i] != 0) continue;
        final m = cand[i];
        if (m == 0) return false;
        if (m & (m - 1) == 0) {
          if (!_place(values, cand, i, RegionsGrid.lowestDigit(m))) return false;
          changed = true;
        }
      }
      for (final cells in grid.regionCells) {
        for (var d = 1; d <= cells.length; d++) {
          final b = RegionsGrid.bit(d);
          var where = -1;
          var count = 0;
          for (final i in cells) {
            if (values[i] == d) {
              count = -1;
              break;
            }
            if (values[i] == 0 && cand[i] & b != 0) {
              count++;
              where = i;
            }
          }
          if (count == 0) return false;
          if (count == 1) {
            if (!_place(values, cand, where, d)) return false;
            changed = true;
          }
        }
      }
    }
    return true;
  }

  int count(int limit, {required bool captureFirst}) => _count(values, cand, limit, captureFirst);

  int _count(List<int> values, List<int> cand, int limit, bool captureFirst) {
    var best = -1;
    var bestCount = 99;
    for (var i = 0; i < values.length; i++) {
      if (values[i] != 0) continue;
      final n = RegionsGrid.bitCount(cand[i]);
      if (n < bestCount) {
        best = i;
        bestCount = n;
        if (n <= 2) break;
      }
    }
    if (best == -1) {
      if (captureFirst && solution == null) solution = List<int>.unmodifiable(values);
      return 1;
    }
    final digits = RegionsGrid.digitsOf(cand[best]).toList(growable: false);
    final rng = nextInt;
    if (rng != null) {
      for (var k = digits.length - 1; k > 0; k--) {
        final j = rng(k + 1);
        final t = digits[k];
        digits[k] = digits[j];
        digits[j] = t;
      }
    }
    var total = 0;
    for (final d in digits) {
      if (maxNodes >= 0 && ++nodes > maxNodes) {
        exhausted = true;
        return total;
      }
      final v2 = List<int>.of(values, growable: false);
      final c2 = List<int>.of(cand, growable: false);
      if (!_place(v2, c2, best, d) || !_propagate(v2, c2)) continue;
      total += _count(v2, c2, limit - total, captureFirst);
      if (total >= limit || exhausted) return total;
    }
    return total;
  }
}
