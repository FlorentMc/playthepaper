import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'regions_grader.dart';
import 'regions_grid.dart';
import 'regions_puzzle.dart';
import 'regions_solver.dart';

/// Deterministic daily boards: the same date always yields the same puzzle,
/// on any platform, from a seed hashed from `regions-<date>`.
///
/// Each attempt partitions the grid into regions of 1 to 5 cells by random
/// growth, fills a solution by randomised search, then removes givens while
/// the solution stays unique. The result must yield to singles and locked
/// candidates alone, so no puzzle needs guessing, and must take at least
/// [minReasoningSteps] steps beyond naked singles, so none is trivial.
class RegionsGenerator {
  RegionsGenerator();

  static const int dailyWidth = 6;
  static const int dailyHeight = 6;
  static const int minGivens = 8;
  static const int maxGivens = 14;
  static const int maxAttempts = 400;

  /// Hidden singles and locked-candidate steps a board must need.
  static const int minReasoningSteps = 2;

  /// Preferred region sizes when growing a region; pockets left behind make
  /// the smaller ones.
  static const List<int> _sizeChoices = [2, 3, 3, 4, 4, 4, 5, 5, 5, 5];

  /// A stable seed for a date, from `regions-<date>`.
  static int seedFor(String date) => fnv1a('regions-$date');

  /// 32-bit FNV-1a over the code units of [text].
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// The record for the calendar date of [date], whatever its time zone.
  PuzzleRecord generate(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final puzzle = generatePuzzle(seed: seedFor(EditionClock.formatDate(day)));
    return PuzzleRecord(
      id: PuzzleId(game: GameKind.regions, date: day),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
  }

  /// A validated puzzle for [seed], retrying derived seeds until one passes
  /// every check.
  static RegionsPuzzle generatePuzzle({
    required int seed,
    int width = dailyWidth,
    int height = dailyHeight,
    int minGivens = minGivens,
    int maxGivens = maxGivens,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final rng = _Rng(_derive(seed, attempt));
      final grid = partition(width, height, rng.nextInt);
      if (grid == null) continue;
      final solution = RegionsSolver.fill(grid, List<int>.filled(grid.cellCount, 0), nextInt: rng.nextInt);
      if (solution == null) continue;
      final givens = carve(grid, solution, rng.nextInt, minGivens: minGivens);
      final count = givens.where((g) => g != 0).length;
      if (count > maxGivens) continue;
      final rating = RegionsGrader.grade(grid, givens);
      if (!rating.solvedByLogic || rating.hiddenSingles + rating.lockedSteps < minReasoningSteps) continue;
      return RegionsPuzzle(grid: grid, givens: givens, solution: solution);
    }
    throw StateError('No regions puzzle found for seed $seed in $maxAttempts attempts');
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// Splits the grid into connected regions of 1 to 5 cells. Each region
  /// starts at the free cell with the fewest free neighbours, so pockets
  /// close before they are stranded, and grows through random free
  /// neighbours towards a size drawn from [_sizeChoices]. Returns null when
  /// the layout has more than one single-cell region or two small regions
  /// touch, which makes for dull or impossible boards.
  ///
  /// Regions are numbered as [RegionsGrid.parse] numbers them, in order of
  /// first appearance, so the board the generator reasons about is the one
  /// the app reads back from the payload.
  static RegionsGrid? partition(int width, int height, int Function(int max) nextInt) {
    final n = width * height;
    final regionOf = List<int>.filled(n, -1);
    List<int> orth(int i) {
      final row = i ~/ width, col = i % width;
      return [
        if (row > 0) i - width,
        if (row < height - 1) i + width,
        if (col > 0) i - 1,
        if (col < width - 1) i + 1,
      ];
    }

    var next = 0;
    while (true) {
      var bestFree = 99;
      final starts = <int>[];
      for (var i = 0; i < n; i++) {
        if (regionOf[i] != -1) continue;
        final free = orth(i).where((j) => regionOf[j] == -1).length;
        if (free < bestFree) {
          bestFree = free;
          starts.clear();
        }
        if (free == bestFree) starts.add(i);
      }
      if (starts.isEmpty) break;
      final start = starts[nextInt(starts.length)];
      final target = _sizeChoices[nextInt(_sizeChoices.length)];
      final region = <int>[start];
      regionOf[start] = next;
      while (region.length < target) {
        final frontier = <int>{};
        for (final c in region) {
          frontier.addAll(orth(c).where((j) => regionOf[j] == -1));
        }
        if (frontier.isEmpty) break;
        final pick = frontier.elementAt(nextInt(frontier.length));
        region.add(pick);
        regionOf[pick] = next;
      }
      next++;
    }
    final grid = RegionsGrid(width: width, height: height, regionOf: regionOf);
    var singles = 0;
    for (final cells in grid.regionCells) {
      if (cells.length == 1) singles++;
    }
    if (singles > 1) return null;
    for (var i = 0; i < n; i++) {
      if (grid.sizeOf(i) > 2) continue;
      for (final j in grid.neighbours[i]) {
        if (j > i && !grid.sameRegion(i, j) && grid.sizeOf(j) <= 2) return null;
      }
    }
    return RegionsGrid.parse(width: width, height: height, regions: grid.regionsString);
  }

  /// Blanks cells of [solution] in random order, keeping every removal that
  /// leaves exactly one solution, until [minGivens] remain.
  static List<int> carve(
    RegionsGrid grid,
    List<int> solution,
    int Function(int max) nextInt, {
    required int minGivens,
  }) {
    final givens = List<int>.of(solution, growable: false);
    final order = List<int>.generate(grid.cellCount, (i) => i);
    for (var k = order.length - 1; k > 0; k--) {
      final j = nextInt(k + 1);
      final t = order[k];
      order[k] = order[j];
      order[j] = t;
    }
    var count = grid.cellCount;
    for (final i in order) {
      if (count <= minGivens) break;
      final v = givens[i];
      givens[i] = 0;
      if (RegionsSolver.countSolutions(grid, givens) == 1) {
        count--;
      } else {
        givens[i] = v;
      }
    }
    return givens;
  }
}

/// A small xorshift generator so the same seed gives the same sequence on
/// every platform.
class _Rng {
  _Rng(int seed) : _state = (seed & 0xFFFFFFFF) == 0 ? 0x2545F491 : seed & 0xFFFFFFFF;

  int _state;

  int nextInt(int max) {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x % max;
  }
}
