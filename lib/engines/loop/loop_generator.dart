import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'loop_grid.dart';
import 'loop_puzzle.dart';
import 'loop_rules.dart';
import 'loop_solver.dart';

/// Deterministic daily puzzles: the same date always gives the same loop, on
/// any platform. A random region of cells is grown, its boundary is the
/// loop, every cell is clued, and clues are then removed while the puzzle
/// stays unique and within reach of one-step reasoning.
class LoopGenerator {
  LoopGenerator();

  static const int width = 6;
  static const int height = 6;
  static const int maxAttempts = 200;

  /// Region sizes to grow, out of 36 cells.
  static const int minRegion = 12;
  static const int maxRegion = 22;

  /// Loops shorter than this are boxes; skip them.
  static const int minLoopLength = 26;

  /// Clues kept after carving: fewer feels bare on a phone, more is filler.
  static const int minClues = 14;
  static const int maxClues = 20;

  /// Edges a player must settle by trying them both ways, on top of the
  /// counting rules: fewer is a giveaway, more is a slog.
  static const int minSteps = 3;
  static const int maxSteps = 14;

  /// A stable seed for a date, from `loop-<date>`.
  static int seedFor(String date) => fnv1a('loop-$date');

  /// 32-bit FNV-1a over the UTF-16 code units of [text].
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  PuzzleRecord generate(DateTime date) {
    final puzzle = generatePuzzle(seedFor(EditionClock.formatDate(date)));
    return PuzzleRecord(
      id: PuzzleId(game: GameKind.loop, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
  }

  /// Tries seeds derived from [seed] until one yields a unique puzzle of
  /// [LoopTier.fair] difficulty with [minClues] to [maxClues] clues.
  static LoopPuzzle generatePuzzle(int seed) {
    final grid = LoopGrid(width, height);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final random = Random(_derive(seed, attempt));
      final region = growRegion(grid, random, minRegion + random.nextInt(maxRegion - minRegion + 1));
      final solution = boundary(grid, region);
      if (solution.where((s) => s).length < minLoopLength) continue;
      final full = fullClues(grid, solution);
      if (LoopRules.violation(grid, full, solution) != null) continue;
      final clues = carve(grid, full, random, target: minClues + random.nextInt(maxClues - minClues + 1));
      final count = clues.where((c) => c >= 0).length;
      if (count < minClues || count > maxClues) continue;
      final deduced = LoopSolver.deduce(grid, clues, List<int>.filled(grid.edgeCount, LoopSolver.unknown));
      if (deduced == null || !deduced.complete || deduced.steps < minSteps || deduced.steps > maxSteps) continue;
      return LoopPuzzle(width: width, height: height, clues: clues, solution: solution);
    }
    throw StateError('No loop puzzle found for seed $seed in $maxAttempts attempts');
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// Grows a 4-connected region of about [size] cells with no holes and no
  /// two cells touching only at a corner, so its boundary is one simple loop.
  /// Cells that would sprout a thin arm are preferred, for a loop that winds.
  static List<bool> growRegion(LoopGrid grid, Random random, int size) {
    final region = List<bool>.filled(grid.cellCount, false);
    region[random.nextInt(grid.cellCount)] = true;
    var count = 1;
    while (count < size) {
      final candidates = <int>[];
      for (var cell = 0; cell < grid.cellCount; cell++) {
        if (!region[cell] && _neighbours(grid, cell).any((n) => region[n])) candidates.add(cell);
      }
      candidates.shuffle(random);
      if (random.nextInt(4) != 0) {
        candidates.sort((a, b) => _regionNeighbours(grid, region, a) - _regionNeighbours(grid, region, b));
      }
      var grown = false;
      for (final cell in candidates) {
        region[cell] = true;
        if (_isSimple(grid, region)) {
          count++;
          grown = true;
          break;
        }
        region[cell] = false;
      }
      if (!grown) break;
    }
    return region;
  }

  /// The edges between a region cell and a non-region cell or the outside.
  static List<bool> boundary(LoopGrid grid, List<bool> region) => List<bool>.generate(
        grid.edgeCount,
        (e) {
          final cells = grid.edgeCells[e];
          final a = region[cells[0]];
          final b = cells.length > 1 && region[cells[1]];
          return a != b;
        },
        growable: false,
      );

  /// Every cell clued with its line count; a cell with four lines is left
  /// blank because clues run 0–3.
  static List<int> fullClues(LoopGrid grid, List<bool> solution) => List<int>.generate(
        grid.cellCount,
        (cell) {
          final n = LoopRules.lineCount(grid.cellEdges[cell], solution);
          return n > 3 ? -1 : n;
        },
        growable: false,
      );

  /// Removes clues in random order while one-step reasoning still settles
  /// every edge in at most [maxSteps] trials, stopping at [target] clues.
  /// A puzzle that reasoning alone completes has exactly one solution.
  static List<int> carve(LoopGrid grid, List<int> full, Random random, {required int target}) {
    final clues = List<int>.of(full, growable: false);
    final order = List<int>.generate(grid.cellCount, (i) => i)..shuffle(random);
    final blank = List<int>.filled(grid.edgeCount, LoopSolver.unknown);
    var count = clues.where((c) => c >= 0).length;
    for (final cell in order) {
      if (count <= target) break;
      if (clues[cell] < 0) continue;
      final kept = clues[cell];
      clues[cell] = -1;
      final deduced = LoopSolver.deduce(grid, clues, blank);
      if (deduced != null && deduced.complete && deduced.steps <= maxSteps) {
        count--;
      } else {
        clues[cell] = kept;
      }
    }
    return clues;
  }

  static List<int> _neighbours(LoopGrid grid, int cell) {
    final r = grid.cellRow(cell), c = grid.cellCol(cell);
    return [
      if (r > 0) grid.cell(r - 1, c),
      if (r < grid.height - 1) grid.cell(r + 1, c),
      if (c > 0) grid.cell(r, c - 1),
      if (c < grid.width - 1) grid.cell(r, c + 1),
    ];
  }

  static int _regionNeighbours(LoopGrid grid, List<bool> region, int cell) =>
      _neighbours(grid, cell).where((n) => region[n]).length;

  /// True when the region's complement (with the outside) is connected and
  /// no dot has region cells on both diagonals only.
  static bool _isSimple(LoopGrid grid, List<bool> region) {
    for (var r = 1; r < grid.height; r++) {
      for (var c = 1; c < grid.width; c++) {
        final a = region[grid.cell(r - 1, c - 1)], b = region[grid.cell(r - 1, c)];
        final d = region[grid.cell(r, c - 1)], e = region[grid.cell(r, c)];
        if (a == e && b == d && a != b) return false;
      }
    }
    final outside = List<bool>.filled(grid.cellCount, false);
    final stack = <int>[];
    for (var cell = 0; cell < grid.cellCount; cell++) {
      final r = grid.cellRow(cell), c = grid.cellCol(cell);
      final border = r == 0 || c == 0 || r == grid.height - 1 || c == grid.width - 1;
      if (border && !region[cell]) {
        outside[cell] = true;
        stack.add(cell);
      }
    }
    while (stack.isNotEmpty) {
      final cell = stack.removeLast();
      for (final n in _neighbours(grid, cell)) {
        if (!region[n] && !outside[n]) {
          outside[n] = true;
          stack.add(n);
        }
      }
    }
    for (var cell = 0; cell < grid.cellCount; cell++) {
      if (!region[cell] && !outside[cell]) return false;
    }
    return true;
  }
}
