import 'loop_grid.dart';

/// The rules of the game, checked against a full set of lines: every clue
/// counts its lines, no dot has a degree other than 0 or 2, and the lines
/// form exactly one closed loop.
class LoopRules {
  LoopRules._();

  /// A one-line description of the first rule the lines break, or null when
  /// they solve the puzzle. [clues] holds -1 for a blank cell.
  static String? violation(LoopGrid grid, List<int> clues, List<bool> lines) {
    if (clues.length != grid.cellCount || lines.length != grid.edgeCount) {
      return 'wrong number of clues or edges';
    }
    final degrees = List<int>.generate(grid.dotCount, (dot) => lineCount(grid.dotEdges[dot], lines), growable: false);
    if (degrees.any((d) => d > 2)) return 'three or more lines meet at a dot';
    if (degrees.contains(1)) return 'the path is open at a dot';
    final lineTotal = degrees.where((d) => d == 2).length;
    final start = degrees.indexOf(2);
    for (var cell = 0; cell < grid.cellCount; cell++) {
      final clue = clues[cell];
      if (clue < 0) continue;
      final count = lineCount(grid.cellEdges[cell], lines);
      if (count != clue) {
        return 'cell row ${grid.cellRow(cell) + 1}, column ${grid.cellCol(cell) + 1} '
            'has $count line${count == 1 ? '' : 's'} but the clue says $clue';
      }
    }
    if (start < 0) return 'no lines drawn';
    if (loopLength(grid, lines, start) != lineTotal) return 'more than one loop';
    return null;
  }

  static bool isSolved(LoopGrid grid, List<int> clues, List<bool> lines) =>
      violation(grid, clues, lines) == null;

  static int lineCount(List<int> edges, List<bool> lines) {
    var n = 0;
    for (final e in edges) {
      if (lines[e]) n++;
    }
    return n;
  }

  /// The number of dots reachable along lines from [start]. Every dot on a
  /// closed loop has degree 2, so this equals the loop's edge count.
  static int loopLength(LoopGrid grid, List<bool> lines, int start) {
    final seen = List<bool>.filled(grid.dotCount, false);
    final stack = <int>[start];
    seen[start] = true;
    var count = 0;
    while (stack.isNotEmpty) {
      final dot = stack.removeLast();
      count++;
      for (final e in grid.dotEdges[dot]) {
        if (!lines[e]) continue;
        final ends = grid.edgeDots[e];
        final next = ends[0] == dot ? ends[1] : ends[0];
        if (!seen[next]) {
          seen[next] = true;
          stack.add(next);
        }
      }
    }
    return count;
  }
}
