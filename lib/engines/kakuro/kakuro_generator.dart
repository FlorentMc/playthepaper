import 'dart:convert';
import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'kakuro_grid.dart';
import 'kakuro_puzzle.dart';
import 'kakuro_solver.dart';

/// Deterministic daily kakuro: the same date always yields the same 6×6
/// board, on any platform. Row 0 and column 0 hold clues; the 5×5 inside is
/// carved into runs of two to five cells, filled with digits, summed, and
/// kept only when the clues have exactly one solution that pure deduction
/// reaches without guessing, and that deduction is not immediate.
class KakuroGenerator {
  KakuroGenerator();

  static const int size = 6;
  static const int minWhiteCells = 10;
  static const int maxAttempts = 200;
  static const int maxRefineSteps = 400;

  /// Solutions counted while refining; anything at or above is "many".
  static const int refineCap = 12;

  /// Deduction must chain through at least this many passes over the runs,
  /// so no daily is read straight off the clues.
  static const int minRounds = 4;

  /// Puzzles whose first pass over the clues already pins more than this
  /// share of the cells are too easy for a daily.
  static const double maxFirstPassShare = 0.5;

  /// A stable seed for a date, from `kakuro-<date>`.
  static int seedFor(String date) => fnv1a('kakuro-$date');

  /// 32-bit FNV-1a over the UTF-8 bytes of [text].
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode(text)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  PuzzleRecord generate(DateTime date) {
    final dateText = EditionClock.formatDate(date);
    final puzzle = generatePuzzle(seedFor(dateText));
    return PuzzleRecord(
      id: PuzzleId(game: GameKind.kakuro, date: EditionClock.parseDate(dateText)),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
  }

  /// The first acceptable puzzle for [seed], trying derived seeds in order.
  static KakuroPuzzle generatePuzzle(int seed) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final puzzle = tryAttempt(Random(_derive(seed, attempt)));
      if (puzzle != null) return puzzle;
    }
    throw StateError('No kakuro found for seed $seed in $maxAttempts attempts');
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// One layout, fill, refinement and check. Null when the board is rejected.
  static KakuroPuzzle? tryAttempt(Random random) {
    final white = carveLayout(random);
    if (white == null) return null;
    final first = fillDigits(white, random);
    if (first == null) return null;
    final digits = refineFill(white, first, random);
    if (digits == null) return null;
    final grid = KakuroGrid(width: size, height: size, cells: clueCells(white, digits));
    if (!isAcceptable(grid)) return null;
    return KakuroPuzzle(grid: grid, solution: digits);
  }

  /// Random digits almost never give unique clues, so walk from [digits]
  /// one cell at a time, keeping every change that does not make the board
  /// worse, until the clues have exactly one solution that deduction alone
  /// reaches. Null when [maxSteps] run out first.
  static List<int>? refineFill(List<bool> white, List<int> digits, Random random, {int maxSteps = maxRefineSteps}) {
    final whites = [for (var i = 0; i < white.length; i++) if (white[i]) i];
    var current = List<int>.of(digits);
    var score = _distance(white, current);
    for (var step = 0; step < maxSteps && score > 0; step++) {
      final i = whites[random.nextInt(whites.length)];
      final free = KakuroGrid.allDigits & ~_lineDigits(white, current, i) & ~KakuroGrid.bit(current[i]);
      if (free == 0) continue;
      final options = KakuroGrid.digitsOf(free).toList();
      final next = List<int>.of(current);
      next[i] = options[random.nextInt(options.length)];
      final nextScore = _distance(white, next);
      if (nextScore <= score) {
        current = next;
        score = nextScore;
      }
    }
    return score == 0 ? current : null;
  }

  /// How far a filled board is from acceptable: the number of solutions
  /// (capped) while there are several, then the number of cells deduction
  /// leaves open. Zero means unique and solved by deduction.
  static int _distance(List<bool> white, List<int> digits) {
    final grid = KakuroGrid(width: size, height: size, cells: clueCells(white, digits));
    final count = KakuroSolver.countSolutions(grid, limit: refineCap);
    if (count != 1) return count * grid.whiteCount;
    return grid.whiteCount - KakuroSolver.deduce(grid).fixedCount(grid);
  }

  /// Digits already used in the across and down lines through [i], excluding [i] itself.
  static int _lineDigits(List<bool> white, List<int> digits, int i) {
    var mask = 0;
    for (var j = i - 1; j >= 0 && j ~/ size == i ~/ size && white[j]; j--) {
      mask |= KakuroGrid.bit(digits[j]);
    }
    for (var j = i + 1; j < white.length && j ~/ size == i ~/ size && white[j]; j++) {
      mask |= KakuroGrid.bit(digits[j]);
    }
    for (var j = i - size; j >= 0 && white[j]; j -= size) {
      mask |= KakuroGrid.bit(digits[j]);
    }
    for (var j = i + size; j < white.length && white[j]; j += size) {
      mask |= KakuroGrid.bit(digits[j]);
    }
    return mask;
  }

  /// Unique, solved by deduction alone, and not trivial: the first pass
  /// pins at most half the cells and the chain runs at least [minRounds].
  static bool isAcceptable(KakuroGrid grid) {
    if (grid.whiteCount < minWhiteCells) return false;
    if (KakuroSolver.countSolutions(grid) != 1) return false;
    final deduction = KakuroSolver.deduce(grid);
    if (!deduction.solves(grid) || deduction.rounds < minRounds) return false;
    return firstPassShare(grid) <= maxFirstPassShare;
  }

  /// The share of white cells pinned by intersecting each cell's two run
  /// combinations, before any cross-run reasoning.
  static double firstPassShare(KakuroGrid grid) {
    var fixed = 0;
    for (final w in grid.whiteCells) {
      var mask = KakuroGrid.allDigits;
      for (final run in grid.runsThrough(w)) {
        var union = 0;
        for (final combo in KakuroSolver.combinations(run.length, run.sum)) {
          union |= combo;
        }
        mask &= union;
      }
      if (KakuroGrid.bitCount(mask) == 1) fixed++;
    }
    return fixed / grid.whiteCount;
  }

  /// A white mask over the board: the inside 5×5 with a few cells blocked so
  /// that every white cell has a white neighbour both across and down, the
  /// white cells stay connected, and at least [minWhiteCells] remain.
  static List<bool>? carveLayout(Random random) {
    final white = List<bool>.filled(size * size, false);
    for (var r = 1; r < size; r++) {
      for (var c = 1; c < size; c++) {
        white[r * size + c] = true;
      }
    }
    final targetBlocks = 2 + random.nextInt(7);
    final order = [for (var r = 1; r < size; r++) for (var c = 1; c < size; c++) r * size + c]..shuffle(random);
    var blocks = 0;
    for (final i in order) {
      if (blocks == targetBlocks) break;
      white[i] = false;
      if (_layoutOk(white)) {
        blocks++;
      } else {
        white[i] = true;
      }
    }
    return blocks == targetBlocks ? white : null;
  }

  static bool _layoutOk(List<bool> white) {
    var count = 0;
    int? start;
    for (var r = 1; r < size; r++) {
      for (var c = 1; c < size; c++) {
        final i = r * size + c;
        if (!white[i]) continue;
        count++;
        start ??= i;
        final across = (c > 1 && white[i - 1]) || (c < size - 1 && white[i + 1]);
        final down = (r > 1 && white[i - size]) || (r < size - 1 && white[i + size]);
        if (!across || !down) return false;
      }
    }
    if (count < minWhiteCells || start == null) return false;
    final seen = List<bool>.filled(size * size, false);
    final stack = [start];
    seen[start] = true;
    var reached = 0;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      reached++;
      for (final j in [i - 1, i + 1, i - size, i + size]) {
        if (j < 0 || j >= size * size || seen[j] || !white[j]) continue;
        seen[j] = true;
        stack.add(j);
      }
    }
    return reached == count;
  }

  /// Digits for every white cell, no repeat within any across or down line.
  static List<int>? fillDigits(List<bool> white, Random random) {
    final digits = List<int>.filled(size * size, 0);
    final order = [for (var i = 0; i < white.length; i++) if (white[i]) i];
    final choices = List<int>.generate(9, (k) => k + 1);

    bool fill(int k) {
      if (k == order.length) return true;
      final i = order[k];
      final taken = _lineDigits(white, digits, i);
      choices.shuffle(random);
      for (final d in choices) {
        if (taken & KakuroGrid.bit(d) != 0) continue;
        digits[i] = d;
        if (fill(k + 1)) return true;
      }
      digits[i] = 0;
      return false;
    }

    return fill(0) ? digits : null;
  }

  /// Blocks, clues and white cells for a filled layout: every non-white cell
  /// that starts a line of white cells carries that line's sum.
  static List<KakuroCell> clueCells(List<bool> white, List<int> digits) {
    return List<KakuroCell>.generate(size * size, (i) {
      if (white[i]) return const KakuroCell.white();
      final r = i ~/ size, c = i % size;
      int? across, down;
      if (c + 1 < size && white[i + 1]) {
        across = 0;
        for (var j = i + 1; j < (r + 1) * size && white[j]; j++) {
          across = across! + digits[j];
        }
      }
      if (r + 1 < size && white[i + size]) {
        down = 0;
        for (var j = i + size; j < size * size && white[j]; j += size) {
          down = down! + digits[j];
        }
      }
      if (across == null && down == null) return const KakuroCell.block();
      return KakuroCell.clue(down: down, across: across);
    });
  }
}
