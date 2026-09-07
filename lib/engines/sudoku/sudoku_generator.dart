import 'dart:math';

import '../../core/game_kind.dart';
import 'sudoku_grader.dart';
import 'sudoku_grid.dart';
import 'sudoku_puzzle.dart';
import 'sudoku_solver.dart';

/// Deterministic puzzle generation: the same seed and difficulty always
/// produce the same puzzle, on any platform.
class SudokuGenerator {
  SudokuGenerator._();

  static const int maxAttempts = 200;

  /// The fewest givens kept per difficulty. Easy and medium puzzles are
  /// carved only as far as their rating allows; hard puzzles are carved as
  /// far as uniqueness allows and must stay at or under [maxHardGivens].
  static const Map<Difficulty, int> minGivens = {
    Difficulty.easy: 36,
    Difficulty.medium: 26,
    Difficulty.hard: 22,
  };
  static const int maxHardGivens = 27;

  /// A stable seed for a puzzle, from `sudoku-<date>-<difficulty>`.
  static int seedFor(String date, Difficulty difficulty) => fnv1a('sudoku-$date-${difficulty.slug}');

  /// 32-bit FNV-1a over the UTF-16 code units of [text].
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static SudokuPuzzle generate({required int seed, required Difficulty difficulty}) {
    final bool Function(List<int>)? accept = switch (difficulty) {
      Difficulty.easy => (g) => SudokuGrader.grade(g).difficulty == Difficulty.easy,
      Difficulty.medium => (g) => SudokuGrader.grade(g).difficulty != Difficulty.hard,
      Difficulty.hard => null,
    };
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final random = Random(_derive(seed, attempt));
      final solution = fillGrid(random);
      final givens = carve(solution, random, minGivens: minGivens[difficulty]!, accept: accept);
      final count = givens.where((g) => g != 0).length;
      if (difficulty == Difficulty.hard && count > maxHardGivens) continue;
      if (SudokuGrader.grade(givens).difficulty != difficulty) continue;
      return SudokuPuzzle(givens: givens, solution: solution);
    }
    throw StateError('No ${difficulty.slug} sudoku found for seed $seed in $maxAttempts attempts');
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// A complete valid grid filled by randomised backtracking.
  static List<int> fillGrid(Random random) {
    final cells = List<int>.filled(SudokuGrid.cellCount, 0);
    final rowMask = List<int>.filled(9, 0);
    final colMask = List<int>.filled(9, 0);
    final boxMask = List<int>.filled(9, 0);
    final digits = List<int>.generate(9, (k) => k + 1);

    bool fill(int i) {
      if (i == SudokuGrid.cellCount) return true;
      final r = SudokuGrid.rowOf[i], c = SudokuGrid.colOf[i], b = SudokuGrid.boxOf[i];
      final used = rowMask[r] | colMask[c] | boxMask[b];
      digits.shuffle(random);
      for (final d in digits) {
        final bit = SudokuGrid.bit(d);
        if (used & bit != 0) continue;
        cells[i] = d;
        rowMask[r] |= bit;
        colMask[c] |= bit;
        boxMask[b] |= bit;
        if (fill(i + 1)) return true;
        rowMask[r] &= ~bit;
        colMask[c] &= ~bit;
        boxMask[b] &= ~bit;
      }
      cells[i] = 0;
      return false;
    }

    fill(0);
    return cells;
  }

  /// Blanks cells in 180° rotationally symmetric pairs, in random order,
  /// keeping every removal that leaves exactly one solution and satisfies
  /// [accept], until fewer than [minGivens] would remain.
  static List<int> carve(
    List<int> solution,
    Random random, {
    required int minGivens,
    bool Function(List<int> givens)? accept,
  }) {
    final givens = List<int>.of(solution, growable: false);
    final pairs = List<int>.generate(41, (i) => i)..shuffle(random);
    var count = SudokuGrid.cellCount;
    for (final a in pairs) {
      final b = SudokuGrid.cellCount - 1 - a;
      final removing = a == b ? 1 : 2;
      if (count - removing < minGivens) continue;
      final va = givens[a], vb = givens[b];
      givens[a] = 0;
      givens[b] = 0;
      if (SudokuSolver.countSolutions(givens) == 1 && (accept == null || accept(givens))) {
        count -= removing;
      } else {
        givens[a] = va;
        givens[b] = vb;
      }
    }
    return givens;
  }
}
