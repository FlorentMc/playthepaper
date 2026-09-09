/// Counts and finds perfect matchings of tiles to cells, given for each tile
/// the cells it fits. Independent of the puzzle classes so content can be
/// checked against it.
class CrossmatchSolver {
  CrossmatchSolver._();

  /// How many ways every tile can take a different cell it fits. [fits] has
  /// one entry per tile listing cell indices; there are as many cells as
  /// tiles. Counted by dynamic programming over the set of used cells.
  static int countMatchings(List<List<int>> fits) {
    final n = fits.length;
    final masks = [for (final cells in fits) cells.fold(0, (m, c) => m | (1 << c))];
    final ways = List<int>.filled(1 << n, 0);
    ways[0] = 1;
    for (var mask = 0; mask < (1 << n); mask++) {
      final count = ways[mask];
      if (count == 0) continue;
      final tile = _popCount(mask);
      if (tile == n) continue;
      final options = masks[tile] & ~mask;
      for (var cell = 0; cell < n; cell++) {
        if (options & (1 << cell) != 0) ways[mask | (1 << cell)] += count;
      }
    }
    return ways[(1 << n) - 1];
  }

  /// The cell of every tile when exactly one matching exists, else null.
  static List<int>? solve(List<List<int>> fits) {
    if (countMatchings(fits) != 1) return null;
    final n = fits.length;
    final assignment = List<int>.filled(n, -1);
    bool assign(int tile, int used) {
      if (tile == n) return true;
      for (final cell in fits[tile]) {
        if (used & (1 << cell) != 0) continue;
        assignment[tile] = cell;
        if (assign(tile + 1, used | (1 << cell))) return true;
      }
      return false;
    }

    return assign(0, 0) ? assignment : null;
  }

  static int _popCount(int mask) {
    var count = 0;
    while (mask != 0) {
      mask &= mask - 1;
      count++;
    }
    return count;
  }
}
