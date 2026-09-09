import 'bridges_layout.dart';

/// How much reasoning a puzzle needs.
enum BridgesRating {
  /// Counting alone settles every bridge: each island's number against the
  /// bridges its neighbours can still take, plus crossings.
  easy,

  /// Also needs the connection argument: a bridge that would seal off a
  /// group of islands cannot be there, and a group's only way out must be.
  medium,

  /// Propagation stalls and a guess is needed.
  hard,
}

/// Lower and upper bounds on the bridges each pair can carry.
class BridgesBounds {
  const BridgesBounds(this.min, this.max);

  final List<int> min;
  final List<int> max;

  bool get isDecided {
    for (var p = 0; p < min.length; p++) {
      if (min[p] != max[p]) return false;
    }
    return true;
  }
}

/// Constraint propagation with backtracking. Propagation narrows the bridge
/// count on every pair; search branches on the tightest undecided pair and
/// counts solutions up to a limit.
class BridgesSolver {
  BridgesSolver._();

  /// The number of solutions, capped at [limit].
  static int countSolutions(BridgesLayout layout, {int limit = 2}) {
    if (limit <= 0) return 0;
    return _Search(layout).count(limit, captureFirst: false);
  }

  /// The first solution found, as bridges per pair, or null when there is none.
  static List<int>? solve(BridgesLayout layout) {
    final search = _Search(layout);
    search.count(1, captureFirst: true);
    return search.solution;
  }

  /// Propagates without guessing, from [lower] bridges already placed (which
  /// are taken as certain). Null when they contradict the puzzle.
  static BridgesBounds? propagate(BridgesLayout layout, {List<int>? lower, bool connection = true}) {
    final search = _Search(layout, lower: lower, connection: connection);
    if (!search.propagate()) return null;
    return BridgesBounds(List.unmodifiable(search.min), List.unmodifiable(search.max));
  }

  static BridgesRating rate(BridgesLayout layout) {
    final counting = propagate(layout, connection: false);
    if (counting != null && counting.isDecided) return BridgesRating.easy;
    final full = propagate(layout);
    if (full != null && full.isDecided) return BridgesRating.medium;
    return BridgesRating.hard;
  }
}

class _Search {
  _Search(this.layout, {List<int>? lower, this.connection = true})
      : min = lower == null ? List<int>.filled(layout.pairs.length, 0) : List<int>.of(lower, growable: false),
        max = List<int>.filled(layout.pairs.length, BridgesLayout.maxBridges) {
    for (var p = 0; p < min.length; p++) {
      if (min[p] < 0 || min[p] > BridgesLayout.maxBridges) throw ArgumentError('Bridges lower bound out of range at pair $p');
    }
  }

  final BridgesLayout layout;
  final bool connection;
  final List<int> min;
  final List<int> max;
  List<int>? solution;

  /// Narrows [min] and [max] until nothing changes. False on contradiction.
  bool propagate() {
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < layout.islands.length; i++) {
        final pairs = layout.pairsOf[i];
        final need = layout.islands[i].count;
        var sumMin = 0, sumMax = 0;
        for (final p in pairs) {
          sumMin += min[p];
          sumMax += max[p];
        }
        if (sumMin > need || sumMax < need) return false;
        for (final p in pairs) {
          final top = need - (sumMin - min[p]);
          if (top < max[p]) {
            max[p] = top;
            changed = true;
          }
          final bottom = need - (sumMax - max[p]);
          if (bottom > min[p]) {
            min[p] = bottom;
            changed = true;
          }
          if (min[p] > max[p]) return false;
        }
      }
      for (final pair in layout.pairs) {
        if (min[pair.index] == 0) continue;
        for (final q in pair.crossings) {
          if (max[q] == 0) continue;
          if (min[q] > 0) return false;
          max[q] = 0;
          changed = true;
        }
      }
      if (connection && layout.islands.length > 2) {
        for (final pair in layout.pairs) {
          final need = layout.islands[pair.a].count;
          if (need != layout.islands[pair.b].count || need > BridgesLayout.maxBridges || max[pair.index] < need) continue;
          max[pair.index] = need - 1;
          changed = true;
          if (min[pair.index] > max[pair.index]) return false;
        }
        final exits = _componentExits();
        if (exits == null) return false;
        for (final p in exits) {
          if (min[p] == 0) {
            min[p] = 1;
            changed = true;
          }
        }
      }
    }
    return true;
  }

  /// For every group of islands already joined by certain bridges, the one
  /// pair that is its only way out, when there is exactly one. Null when a
  /// group short of the whole board has no way out at all.
  List<int>? _componentExits() {
    final n = layout.islands.length;
    final component = List<int>.filled(n, -1);
    final forced = <int>[];
    var groups = 0;
    for (var start = 0; start < n; start++) {
      if (component[start] != -1) continue;
      final id = groups++;
      final members = <int>[start];
      component[start] = id;
      for (var k = 0; k < members.length; k++) {
        for (final p in layout.pairsOf[members[k]]) {
          if (min[p] == 0) continue;
          final j = layout.pairs[p].other(members[k]);
          if (component[j] != -1) continue;
          component[j] = id;
          members.add(j);
        }
      }
      if (members.length == n) return forced;
      var exit = -1, exits = 0;
      for (final i in members) {
        for (final p in layout.pairsOf[i]) {
          if (max[p] == 0 || component[layout.pairs[p].other(i)] == id) continue;
          exits++;
          exit = p;
        }
      }
      if (exits == 0) return null;
      if (exits == 1) forced.add(exit);
    }
    return forced;
  }

  int count(int limit, {required bool captureFirst}) {
    if (!propagate()) return 0;
    var best = -1, width = BridgesLayout.maxBridges + 2;
    for (var p = 0; p < min.length; p++) {
      final w = max[p] - min[p];
      if (w > 0 && w < width) {
        best = p;
        width = w;
      }
    }
    if (best == -1) {
      if (!layout.isConnected(min)) return 0;
      if (captureFirst && solution == null) solution = List<int>.unmodifiable(min);
      return 1;
    }
    final savedMin = List<int>.of(min, growable: false);
    final savedMax = List<int>.of(max, growable: false);
    var total = 0;
    for (var v = savedMin[best]; v <= savedMax[best]; v++) {
      min[best] = v;
      max[best] = v;
      total += count(limit - total, captureFirst: captureFirst);
      min.setAll(0, savedMin);
      max.setAll(0, savedMax);
      if (total >= limit) return total;
    }
    return total;
  }
}
