import 'kakuro_grid.dart';

/// What pure deduction establishes from the clues alone, before any guessing.
class KakuroDeduction {
  const KakuroDeduction({required this.candidates, required this.consistent, required this.rounds});

  /// Candidate bitmask per cell, 0 for cells that are not white.
  final List<int> candidates;

  /// False when the clues contradict each other.
  final bool consistent;

  /// Passes over the runs until nothing more could be narrowed.
  final int rounds;

  bool isFixed(int cell) => candidates[cell] != 0 && candidates[cell] & (candidates[cell] - 1) == 0;

  /// True when every white cell was pinned to a single digit.
  bool solves(KakuroGrid grid) => consistent && grid.whiteCells.every(isFixed);

  int fixedCount(KakuroGrid grid) => grid.whiteCells.where(isFixed).length;
}

/// Run-combination constraint propagation with backtracking, always
/// branching on the white cell with the fewest candidates.
class KakuroSolver {
  KakuroSolver._();

  static final Map<int, List<int>> _combos = {};

  /// Every set of [length] different digits summing to [sum], as bitmasks.
  static List<int> combinations(int length, int sum) {
    return _combos.putIfAbsent(length * 64 + sum, () {
      final out = <int>[];
      void walk(int from, int left, int need, int mask) {
        if (left == 0) {
          if (need == 0) out.add(mask);
          return;
        }
        for (var d = from; d <= 9; d++) {
          if (need - d < KakuroGrid.minSum(left - 1)) break;
          walk(d + 1, left - 1, need - d, mask | KakuroGrid.bit(d));
        }
      }

      if (length >= 1 && length <= 9) walk(1, length, sum, 0);
      return List<int>.unmodifiable(out);
    });
  }

  /// The number of solutions, capped at [limit].
  static int countSolutions(KakuroGrid grid, {int limit = 2}) {
    if (limit <= 0) return 0;
    return _Search(grid).count(_Search.initial(grid), limit, captureFirst: false);
  }

  /// The first solution found (one int per cell, 0 where not white), or null.
  static List<int>? solve(KakuroGrid grid) {
    final search = _Search(grid);
    search.count(_Search.initial(grid), 1, captureFirst: true);
    return search.solution;
  }

  /// Propagation alone from the initial candidates, with no branching.
  static KakuroDeduction deduce(KakuroGrid grid) {
    final search = _Search(grid);
    final cands = _Search.initial(grid);
    final consistent = search.propagate(cands);
    return KakuroDeduction(
      candidates: List<int>.unmodifiable(cands),
      consistent: consistent,
      rounds: search.lastRounds,
    );
  }
}

class _Search {
  _Search(this.grid) : runCombos = [for (final run in grid.runs) KakuroSolver.combinations(run.length, run.sum)];

  final KakuroGrid grid;
  final List<List<int>> runCombos;
  List<int>? solution;
  int lastRounds = 0;

  static List<int> initial(KakuroGrid grid) {
    final cands = List<int>.filled(grid.cellCount, 0);
    for (final w in grid.whiteCells) {
      cands[w] = KakuroGrid.allDigits;
    }
    return cands;
  }

  static bool _single(int mask) => mask != 0 && mask & (mask - 1) == 0;

  /// Narrows [cands] in place until stable. Returns false on a contradiction.
  bool propagate(List<int> cands) {
    lastRounds = 0;
    var changed = true;
    while (changed) {
      changed = false;
      lastRounds++;
      for (var r = 0; r < grid.runs.length; r++) {
        final run = grid.runs[r];
        var union = 0;
        var fixed = 0;
        for (final c in run.cells) {
          final m = cands[c];
          union |= m;
          if (_single(m)) {
            if (fixed & m != 0) return false;
            fixed |= m;
          }
        }
        var allowed = 0;
        var must = KakuroGrid.allDigits;
        for (final combo in runCombos[r]) {
          if (combo & ~union != 0 || fixed & ~combo != 0) continue;
          var fits = true;
          for (final c in run.cells) {
            if (cands[c] & combo == 0) {
              fits = false;
              break;
            }
          }
          if (!fits) continue;
          allowed |= combo;
          must &= combo;
        }
        if (allowed == 0) return false;
        for (final c in run.cells) {
          var m = cands[c] & allowed;
          if (!_single(cands[c])) m &= ~fixed;
          if (m == 0) return false;
          if (m != cands[c]) {
            cands[c] = m;
            changed = true;
          }
        }
        var pending = must & ~fixed;
        while (pending != 0) {
          final b = pending & -pending;
          pending ^= b;
          var holders = 0;
          var only = -1;
          for (final c in run.cells) {
            if (cands[c] & b != 0) {
              holders++;
              only = c;
            }
          }
          if (holders == 0) return false;
          if (holders == 1 && cands[only] != b) {
            cands[only] = b;
            changed = true;
          }
        }
      }
    }
    return true;
  }

  int count(List<int> cands, int limit, {required bool captureFirst}) {
    if (!propagate(cands)) return 0;
    var best = -1;
    var bestCount = 10;
    for (final w in grid.whiteCells) {
      final n = KakuroGrid.bitCount(cands[w]);
      if (n > 1 && n < bestCount) {
        best = w;
        bestCount = n;
        if (n == 2) break;
      }
    }
    if (best == -1) {
      if (captureFirst && solution == null) {
        solution = List<int>.unmodifiable([for (final m in cands) m == 0 ? 0 : m.bitLength - 1]);
      }
      return 1;
    }
    var total = 0;
    var mask = cands[best];
    while (mask != 0) {
      final low = mask & -mask;
      mask ^= low;
      final branch = List<int>.of(cands, growable: false);
      branch[best] = low;
      total += count(branch, limit - total, captureFirst: captureFirst);
      if (total >= limit) return total;
    }
    return total;
  }
}
