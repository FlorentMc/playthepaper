import 'target_expression.dart';

/// One way of reaching a value: the expression and how many tiles it uses.
class TargetSolution {
  const TargetSolution(this.expression);

  final TargetExpression expression;

  int get tilesUsed => expression.numbers.length;
}

/// Exhaustive search over every way of combining the tiles: every subset,
/// every pairing of two smaller subsets, every operation, positive whole
/// intermediates and exact division only. Built once per tile set, then any
/// target can be looked up.
class TargetSearch {
  TargetSearch(List<int> tiles)
      : tiles = List<int>.unmodifiable(tiles),
        _reach = List<Map<int, TargetExpression>?>.filled(1 << tiles.length, null) {
    if (tiles.length > 8) throw ArgumentError('TargetSearch supports at most 8 tiles');
    final n = tiles.length;
    for (var mask = 1; mask < (1 << n); mask++) {
      final found = <int, TargetExpression>{};
      if (_bitCount(mask) == 1) {
        final i = mask.bitLength - 1;
        found[tiles[i]] = TargetNumber(tiles[i]);
      } else {
        for (var sub = (mask - 1) & mask; sub > 0; sub = (sub - 1) & mask) {
          final rest = mask ^ sub;
          if (sub > rest) continue;
          _combine(_reach[sub]!, _reach[rest]!, found);
          _combine(_reach[rest]!, _reach[sub]!, found);
        }
      }
      _reach[mask] = found;
    }
  }

  final List<int> tiles;
  final List<Map<int, TargetExpression>?> _reach;

  static void _combine(Map<int, TargetExpression> left, Map<int, TargetExpression> right, Map<int, TargetExpression> out) {
    for (final a in left.entries) {
      for (final b in right.entries) {
        for (final op in TargetOp.values) {
          final v = op.apply(a.key, b.key);
          if (v == null || out.containsKey(v)) continue;
          out[v] = TargetBinary(a.value, op, b.value);
        }
      }
    }
  }

  static int _bitCount(int mask) {
    var n = 0;
    for (var x = mask; x != 0; x &= x - 1) {
      n++;
    }
    return n;
  }

  /// The solution using the fewest tiles, or null when [target] cannot be made.
  TargetSolution? solve(int target) {
    TargetExpression? best;
    var bestTiles = tiles.length + 1;
    for (var mask = 1; mask < _reach.length; mask++) {
      final count = _bitCount(mask);
      if (count >= bestTiles) continue;
      final e = _reach[mask]![target];
      if (e != null) {
        best = e;
        bestTiles = count;
      }
    }
    return best == null ? null : TargetSolution(best);
  }

  bool isReachable(int target) => solve(target) != null;

  /// How many tiles the shortest solution needs, or null when unreachable.
  int? minTiles(int target) => solve(target)?.tilesUsed;

  /// The reachable value nearest to [target], and how far off it is.
  (int value, int off) closest(int target) {
    var bestValue = tiles.first;
    var bestOff = (target - bestValue).abs();
    for (var mask = 1; mask < _reach.length; mask++) {
      for (final v in _reach[mask]!.keys) {
        final off = (target - v).abs();
        if (off < bestOff || (off == bestOff && v < bestValue)) {
          bestValue = v;
          bestOff = off;
        }
      }
    }
    return (bestValue, bestOff);
  }
}
