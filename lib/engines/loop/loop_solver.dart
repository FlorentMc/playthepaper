import 'loop_grid.dart';
import 'loop_rules.dart';

/// How much reasoning a puzzle needs. [trivial] falls to the counting rules
/// alone; [fair] needs those plus trying one edge at a time and seeing where
/// it leads; [hard] needs deeper search.
enum LoopTier { trivial, fair, hard }

/// What one-step reasoning reaches from a position.
class LoopDeduction {
  const LoopDeduction(this.values, this.steps);

  /// One value per edge; [LoopSolver.unknown] where reasoning ran out.
  final List<int> values;

  /// Edges settled by trying them both ways.
  final int steps;

  bool get complete => !values.contains(LoopSolver.unknown);
}

/// Propagation on dot degrees and cell counts, with backtracking that counts
/// solutions up to a limit. Edge values are [unknown], 0 (no line) or 1.
class LoopSolver {
  LoopSolver._();

  static const int unknown = -1;

  /// The number of solutions, capped at [limit]. [known] fixes edges first;
  /// a fixed set that already breaks a rule has none.
  static int countSolutions(LoopGrid grid, List<int> clues, {List<int>? known, int limit = 2}) {
    if (limit <= 0) return 0;
    final values = _start(grid, known);
    if (values == null) return 0;
    return _Search(grid, clues, limit).count(values);
  }

  /// The first solution found, as lines, or null when there is none.
  static List<bool>? solve(LoopGrid grid, List<int> clues, {List<int>? known}) {
    final values = _start(grid, known);
    if (values == null) return null;
    final search = _Search(grid, clues, 1);
    search.count(values);
    return search.solution;
  }

  /// The values forced from [values] by the counting rules alone, or null
  /// when they contradict each other.
  static List<int>? propagate(LoopGrid grid, List<int> clues, List<int> values) {
    final work = List<int>.of(values, growable: false);
    return _Propagation(grid, clues, work).runAll() ? work : null;
  }

  /// [propagate], then try each unknown edge both ways and rule out a value
  /// that leads to a contradiction, until every edge is settled or nothing
  /// more gives. Returns null when [values] contradict each other.
  static LoopDeduction? deduce(LoopGrid grid, List<int> clues, List<int> values) {
    final start = propagate(grid, clues, values);
    if (start == null) return null;
    var current = start;
    var steps = 0;
    var changed = true;
    while (changed) {
      changed = false;
      for (var edge = 0; edge < grid.edgeCount; edge++) {
        if (current[edge] != unknown) continue;
        final withLine = _trial(grid, clues, current, edge, 1);
        final withCross = _trial(grid, clues, current, edge, 0);
        if (withLine == null && withCross == null) return null;
        if (withLine == null || withCross == null) {
          current = (withLine ?? withCross)!;
          steps++;
          changed = true;
        }
      }
    }
    return LoopDeduction(current, steps);
  }

  /// Grades [clues] by the reasoning needed to reach the solution. A puzzle
  /// without a unique solution is [LoopTier.hard].
  static LoopTier tier(LoopGrid grid, List<int> clues) {
    final deduced = deduce(grid, clues, List<int>.filled(grid.edgeCount, unknown));
    if (deduced == null || !deduced.complete) return LoopTier.hard;
    return deduced.steps == 0 ? LoopTier.trivial : LoopTier.fair;
  }

  static List<int>? _trial(LoopGrid grid, List<int> clues, List<int> values, int edge, int value) {
    final work = List<int>.of(values, growable: false);
    final prop = _Propagation(grid, clues, work);
    if (!prop.set(edge, value) || !prop.run()) return null;
    return work;
  }

  static List<int>? _start(LoopGrid grid, List<int>? known) {
    final values = List<int>.filled(grid.edgeCount, unknown);
    if (known == null) return values;
    if (known.length != grid.edgeCount) throw ArgumentError('known must have ${grid.edgeCount} edges');
    for (var e = 0; e < grid.edgeCount; e++) {
      final k = known[e];
      if (k == unknown) continue;
      if (k != 0 && k != 1) throw ArgumentError('edge values are -1, 0 or 1');
      values[e] = k;
    }
    return values;
  }
}

class _Search {
  _Search(this.grid, this.clues, this.limit);

  final LoopGrid grid;
  final List<int> clues;
  final int limit;
  List<bool>? solution;
  int found = 0;

  int count(List<int> values) {
    if (!_Propagation(grid, clues, values).runAll()) return 0;
    final edge = _choose(values);
    if (edge < 0) {
      final lines = List<bool>.generate(grid.edgeCount, (e) => values[e] == 1, growable: false);
      if (LoopRules.violation(grid, clues, lines) != null) return 0;
      solution ??= lines;
      found++;
      return 1;
    }
    var total = 0;
    for (final value in const [1, 0]) {
      final branch = List<int>.of(values, growable: false);
      branch[edge] = value;
      total += count(branch);
      if (found >= limit) return total;
    }
    return total;
  }

  /// An unknown edge at the end of a path first, then one of the most
  /// constrained unfinished clue, then any.
  int _choose(List<int> values) {
    var best = -1;
    var bestScore = 1 << 20;
    for (var dot = 0; dot < grid.dotCount; dot++) {
      var lines = 0, open = 0, candidate = -1;
      for (final e in grid.dotEdges[dot]) {
        if (values[e] == 1) {
          lines++;
        } else if (values[e] == LoopSolver.unknown) {
          open++;
          candidate = e;
        }
      }
      if (lines == 1 && open > 0 && open < bestScore) {
        best = candidate;
        bestScore = open;
      }
    }
    if (best >= 0) return best;
    for (var cell = 0; cell < grid.cellCount; cell++) {
      final clue = clues[cell];
      if (clue < 0) continue;
      var lines = 0, open = 0, candidate = -1;
      for (final e in grid.cellEdges[cell]) {
        if (values[e] == 1) {
          lines++;
        } else if (values[e] == LoopSolver.unknown) {
          open++;
          candidate = e;
        }
      }
      if (lines < clue && open > 0 && open < bestScore) {
        best = candidate;
        bestScore = open;
      }
    }
    if (best >= 0) return best;
    for (var e = 0; e < grid.edgeCount; e++) {
      if (values[e] == LoopSolver.unknown) return e;
    }
    return -1;
  }
}

/// Worklist propagation over a mutable value list. Cells and dots are queued
/// whenever one of their edges is set; a closed loop ends the puzzle, so
/// closing one early with anything left over is a contradiction.
class _Propagation {
  _Propagation(this.grid, this.clues, this.values)
      : _queued = List<bool>.filled(grid.cellCount + grid.dotCount, false);

  final LoopGrid grid;
  final List<int> clues;
  final List<int> values;
  final List<bool> _queued;
  final List<int> _queue = [];

  bool set(int edge, int value) {
    final current = values[edge];
    if (current == value) return true;
    if (current != LoopSolver.unknown) return false;
    values[edge] = value;
    for (final cell in grid.edgeCells[edge]) {
      _enqueue(cell);
    }
    for (final dot in grid.edgeDots[edge]) {
      _enqueue(grid.cellCount + dot);
    }
    return true;
  }

  void _enqueue(int item) {
    if (_queued[item]) return;
    _queued[item] = true;
    _queue.add(item);
  }

  /// Queues everything, then [run]s.
  bool runAll() {
    for (var i = 0; i < _queued.length; i++) {
      _enqueue(i);
    }
    return run();
  }

  bool run() {
    while (_queue.isNotEmpty) {
      final item = _queue.removeLast();
      _queued[item] = false;
      final ok = item < grid.cellCount ? _checkCell(item) : _checkDot(item - grid.cellCount);
      if (!ok) return false;
    }
    return _closeLoop();
  }

  bool _checkCell(int cell) {
    final clue = clues[cell];
    if (clue < 0) return true;
    var lines = 0, open = 0;
    for (final e in grid.cellEdges[cell]) {
      if (values[e] == 1) {
        lines++;
      } else if (values[e] == LoopSolver.unknown) {
        open++;
      }
    }
    if (lines > clue || lines + open < clue) return false;
    if (open == 0) return true;
    if (lines == clue) return _fillOpen(grid.cellEdges[cell], 0);
    if (lines + open == clue) return _fillOpen(grid.cellEdges[cell], 1);
    return true;
  }

  bool _checkDot(int dot) {
    var lines = 0, open = 0;
    for (final e in grid.dotEdges[dot]) {
      if (values[e] == 1) {
        lines++;
      } else if (values[e] == LoopSolver.unknown) {
        open++;
      }
    }
    if (lines > 2 || (lines == 1 && open == 0)) return false;
    if (open == 0) return true;
    if (lines == 2 || (lines == 0 && open == 1)) return _fillOpen(grid.dotEdges[dot], 0);
    if (lines == 1 && open == 1) return _fillOpen(grid.dotEdges[dot], 1);
    return true;
  }

  bool _fillOpen(List<int> edges, int value) {
    for (final e in edges) {
      if (values[e] == LoopSolver.unknown && !set(e, value)) return false;
    }
    return true;
  }

  /// If the lines already close a loop, that loop is the whole answer:
  /// every clue must be met and every other edge empty.
  bool _closeLoop() {
    var lineTotal = 0;
    for (var e = 0; e < grid.edgeCount; e++) {
      if (values[e] == 1) lineTotal++;
    }
    if (lineTotal == 0) return true;
    final visited = List<bool>.filled(grid.dotCount, false);
    for (var start = 0; start < grid.dotCount; start++) {
      if (visited[start] || _degree(start) != 2) continue;
      var dot = start;
      var from = -1;
      var length = 0;
      while (true) {
        visited[dot] = true;
        var next = -1;
        for (final e in grid.dotEdges[dot]) {
          if (values[e] == 1 && e != from) {
            next = e;
            break;
          }
        }
        if (next < 0) break;
        length++;
        final ends = grid.edgeDots[next];
        dot = ends[0] == dot ? ends[1] : ends[0];
        from = next;
        if (dot == start) {
          if (length != lineTotal) return false;
          final lines = _lines();
          for (var cell = 0; cell < grid.cellCount; cell++) {
            if (clues[cell] >= 0 && LoopRules.lineCount(grid.cellEdges[cell], lines) != clues[cell]) return false;
          }
          for (var e = 0; e < grid.edgeCount; e++) {
            if (values[e] == LoopSolver.unknown) values[e] = 0;
          }
          return true;
        }
        if (_degree(dot) != 2) break;
      }
    }
    return true;
  }

  int _degree(int dot) {
    var n = 0;
    for (final e in grid.dotEdges[dot]) {
      if (values[e] == 1) n++;
    }
    return n;
  }

  List<bool> _lines() => List<bool>.generate(grid.edgeCount, (e) => values[e] == 1, growable: false);
}
