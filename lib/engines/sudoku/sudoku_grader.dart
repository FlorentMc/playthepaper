import '../../core/game_kind.dart';
import 'sudoku_grid.dart';

enum SudokuTechnique {
  nakedSingle('Naked single'),
  hiddenSingle('Hidden single'),
  nakedPair('Naked pair'),
  hiddenPair('Hidden pair'),
  pointingPair('Pointing pair or triple'),
  boxLineReduction('Box/line reduction');

  const SudokuTechnique(this.label);
  final String label;

  bool get isSingle => this == nakedSingle || this == hiddenSingle;
}

class SudokuGrade {
  const SudokuGrade({required this.difficulty, required this.techniques, required this.solved});

  final Difficulty difficulty;

  /// Every technique the logical solver needed, in the order first used.
  final List<SudokuTechnique> techniques;

  /// False when the puzzle needs techniques beyond those implemented.
  final bool solved;
}

/// Rates a puzzle by the techniques a human needs to solve it without
/// guessing: singles only is easy, pairs and box/line interactions are
/// medium, anything harder is hard.
class SudokuGrader {
  SudokuGrader._();

  static SudokuGrade grade(List<int> givens) {
    final solver = _LogicalSolver(givens);
    final used = <SudokuTechnique>[];
    final steps = <(SudokuTechnique, bool Function())>[
      (SudokuTechnique.nakedSingle, solver.nakedSingles),
      (SudokuTechnique.hiddenSingle, solver.hiddenSingles),
      (SudokuTechnique.nakedPair, solver.nakedPairs),
      (SudokuTechnique.hiddenPair, solver.hiddenPairs),
      (SudokuTechnique.pointingPair, solver.pointingPairs),
      (SudokuTechnique.boxLineReduction, solver.boxLineReductions),
    ];
    progress:
    while (solver.consistent && !solver.isSolved) {
      for (final (technique, apply) in steps) {
        if (apply()) {
          if (!used.contains(technique)) used.add(technique);
          continue progress;
        }
      }
      break;
    }
    final solved = solver.consistent && solver.isSolved;
    final Difficulty difficulty;
    if (!solved) {
      difficulty = Difficulty.hard;
    } else if (used.every((t) => t.isSingle)) {
      difficulty = Difficulty.easy;
    } else {
      difficulty = Difficulty.medium;
    }
    return SudokuGrade(difficulty: difficulty, techniques: List.unmodifiable(used), solved: solved);
  }
}

class _LogicalSolver {
  _LogicalSolver(List<int> givens)
      : values = List<int>.of(givens, growable: false),
        candidates = List<int>.filled(SudokuGrid.cellCount, 0) {
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      if (values[i] != 0) continue;
      var mask = SudokuGrid.allDigits;
      for (final p in SudokuGrid.peers[i]) {
        if (values[p] != 0) mask &= ~SudokuGrid.bit(values[p]);
      }
      candidates[i] = mask;
      if (mask == 0) consistent = false;
    }
    empty = values.where((v) => v == 0).length;
  }

  final List<int> values;
  final List<int> candidates;
  bool consistent = true;
  late int empty;

  bool get isSolved => empty == 0;

  void _place(int i, int d) {
    values[i] = d;
    candidates[i] = 0;
    empty--;
    final clear = ~SudokuGrid.bit(d);
    for (final p in SudokuGrid.peers[i]) {
      if (values[p] == 0) {
        candidates[p] &= clear;
        if (candidates[p] == 0) consistent = false;
      }
    }
  }

  bool nakedSingles() {
    var progress = false;
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      if (values[i] != 0 || SudokuGrid.bitCount(candidates[i]) != 1) continue;
      _place(i, SudokuGrid.lowestDigit(candidates[i]));
      progress = true;
      if (!consistent) return true;
    }
    return progress;
  }

  bool hiddenSingles() {
    var progress = false;
    for (final unit in SudokuGrid.units) {
      for (var d = 1; d <= 9; d++) {
        final b = SudokuGrid.bit(d);
        var where = -1;
        var n = 0;
        for (final i in unit) {
          if (values[i] == d) {
            n = -1;
            break;
          }
          if (candidates[i] & b != 0) {
            n++;
            where = i;
          }
        }
        if (n == 1) {
          _place(where, d);
          progress = true;
          if (!consistent) return true;
        }
      }
    }
    return progress;
  }

  bool nakedPairs() {
    var progress = false;
    for (final unit in SudokuGrid.units) {
      for (var a = 0; a < 9; a++) {
        final ca = candidates[unit[a]];
        if (values[unit[a]] != 0 || SudokuGrid.bitCount(ca) != 2) continue;
        for (var b = a + 1; b < 9; b++) {
          if (values[unit[b]] != 0 || candidates[unit[b]] != ca) continue;
          for (var k = 0; k < 9; k++) {
            if (k == a || k == b) continue;
            final i = unit[k];
            if (values[i] == 0 && candidates[i] & ca != 0) {
              candidates[i] &= ~ca;
              if (candidates[i] == 0) consistent = false;
              progress = true;
            }
          }
        }
      }
    }
    return progress;
  }

  bool hiddenPairs() {
    var progress = false;
    final positions = List<int>.filled(10, 0);
    for (final unit in SudokuGrid.units) {
      for (var d = 1; d <= 9; d++) {
        var mask = 0;
        for (var k = 0; k < 9; k++) {
          if (values[unit[k]] == 0 && candidates[unit[k]] & SudokuGrid.bit(d) != 0) mask |= 1 << k;
        }
        positions[d] = mask;
      }
      for (var d1 = 1; d1 <= 9; d1++) {
        if (SudokuGrid.bitCount(positions[d1]) != 2) continue;
        for (var d2 = d1 + 1; d2 <= 9; d2++) {
          if (positions[d2] != positions[d1]) continue;
          final keep = SudokuGrid.bit(d1) | SudokuGrid.bit(d2);
          for (var k = 0; k < 9; k++) {
            if (positions[d1] & (1 << k) == 0) continue;
            final i = unit[k];
            if (candidates[i] & ~keep != 0) {
              candidates[i] &= keep;
              progress = true;
            }
          }
        }
      }
    }
    return progress;
  }

  /// A digit confined to one row or column inside a box leaves that line
  /// elsewhere.
  bool pointingPairs() {
    var progress = false;
    for (var b = 0; b < 9; b++) {
      for (var d = 1; d <= 9; d++) {
        final bit = SudokuGrid.bit(d);
        var rowsSeen = 0;
        var colsSeen = 0;
        var n = 0;
        for (final i in SudokuGrid.boxes[b]) {
          if (values[i] == 0 && candidates[i] & bit != 0) {
            rowsSeen |= 1 << SudokuGrid.rowOf[i];
            colsSeen |= 1 << SudokuGrid.colOf[i];
            n++;
          }
        }
        if (n < 2) continue;
        if (SudokuGrid.bitCount(rowsSeen) == 1) {
          final r = rowsSeen.bitLength - 1;
          if (_eliminateOutsideBox(SudokuGrid.rows[r], b, bit)) progress = true;
        } else if (SudokuGrid.bitCount(colsSeen) == 1) {
          final c = colsSeen.bitLength - 1;
          if (_eliminateOutsideBox(SudokuGrid.cols[c], b, bit)) progress = true;
        }
      }
    }
    return progress;
  }

  bool _eliminateOutsideBox(List<int> line, int box, int bit) {
    var progress = false;
    for (final i in line) {
      if (SudokuGrid.boxOf[i] == box || values[i] != 0 || candidates[i] & bit == 0) continue;
      candidates[i] &= ~bit;
      if (candidates[i] == 0) consistent = false;
      progress = true;
    }
    return progress;
  }

  /// A digit confined to one box within a row or column leaves the rest of
  /// that box.
  bool boxLineReductions() {
    var progress = false;
    for (final line in [...SudokuGrid.rows, ...SudokuGrid.cols]) {
      for (var d = 1; d <= 9; d++) {
        final bit = SudokuGrid.bit(d);
        var boxesSeen = 0;
        var n = 0;
        for (final i in line) {
          if (values[i] == 0 && candidates[i] & bit != 0) {
            boxesSeen |= 1 << SudokuGrid.boxOf[i];
            n++;
          }
        }
        if (n < 2 || SudokuGrid.bitCount(boxesSeen) != 1) continue;
        final box = boxesSeen.bitLength - 1;
        for (final i in SudokuGrid.boxes[box]) {
          if (line.contains(i) || values[i] != 0 || candidates[i] & bit == 0) continue;
          candidates[i] &= ~bit;
          if (candidates[i] == 0) consistent = false;
          progress = true;
        }
      }
    }
    return progress;
  }
}
