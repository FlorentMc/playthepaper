import 'dart:convert';
import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'binary_puzzle.dart';
import 'binary_rules.dart';
import 'binary_solver.dart';

/// Deterministic Takuzu generation: the same date always yields the same
/// puzzle, on any platform. A full grid is filled at random, then cells are
/// blanked in random order while the rules alone still complete the grid,
/// so every published puzzle is solvable without guessing. A puzzle is
/// rejected as too easy when the pair-and-gap rule alone leaves fewer than
/// [minCellsBeyondBasic] cells for the counting and no-repeat rules.
class BinaryGenerator {
  BinaryGenerator();

  static const int dailySize = 8;
  static const int maxAttempts = 200;
  static const int minCellsBeyondBasic = 10;

  /// Givens kept on the daily 8×8; other sizes scale the same fractions.
  static int minGivensFor(int size) => (size * size * 26 / 64).round();
  static int maxGivensFor(int size) => (size * size * 34 / 64).round();

  /// A stable seed for a date, from `binary-<date>`.
  static int seedFor(String date) => fnv1a('binary-$date');

  /// Stable 32-bit FNV-1a hash, the same as the content tools use.
  static int fnv1a(String input) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  PuzzleRecord generate(DateTime date) {
    final puzzle = generatePuzzle(seed: seedFor(EditionClock.formatDate(date)));
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.binary, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    final parsed = BinaryPuzzle.parse(check.payload, check.reveal);
    if (parsed.givensString != puzzle.givensString || parsed.solutionString != puzzle.solutionString) {
      throw StateError('Round trip failed for ${record.id}');
    }
    return record;
  }

  static BinaryPuzzle generatePuzzle({required int seed, int size = dailySize, int? minGivens, int? maxGivens}) {
    BinaryRules.checkSize(size);
    final low = minGivens ?? minGivensFor(size);
    final high = maxGivens ?? maxGivensFor(size);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final random = Random(_derive(seed, attempt));
      final solution = fillGrid(random, size);
      final target = low + random.nextInt(high - low + 1);
      final givens = carve(solution, random, size, target: target);
      final count = givens.where((g) => g != BinaryRules.empty).length;
      if (count > high) continue;
      if (cellsBeyondBasic(givens, size) < minCellsBeyondBasic) continue;
      if (BinarySolver.countSolutions(givens, size) != 1) continue;
      return BinaryPuzzle(size: size, givens: givens, solution: solution);
    }
    throw StateError('No binary puzzle of size $size found for seed $seed in $maxAttempts attempts');
  }

  /// How many cells the pair-and-gap rule alone cannot fill.
  static int cellsBeyondBasic(List<int> givens, int size) {
    final basic = BinarySolver.propagate(givens, size, basicOnly: true);
    if (basic == null) return 0;
    return basic.where((v) => v == BinaryRules.empty).length;
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// A complete valid grid filled by randomised backtracking.
  static List<int> fillGrid(Random random, int size) {
    final cells = List<int>.filled(size * size, BinaryRules.empty);
    final half = size ~/ 2;
    final rowCount = List.generate(size, (_) => [0, 0]);
    final colCount = List.generate(size, (_) => [0, 0]);

    bool ok(int i, int v) {
      final r = i ~/ size, c = i % size;
      if (rowCount[r][v] >= half || colCount[c][v] >= half) return false;
      if (c >= 2 && cells[i - 1] == v && cells[i - 2] == v) return false;
      if (r >= 2 && cells[i - size] == v && cells[i - 2 * size] == v) return false;
      return true;
    }

    bool duplicatesEarlier(int i) {
      final r = i ~/ size, c = i % size;
      if (c == size - 1) {
        for (var other = 0; other < r; other++) {
          var same = true;
          for (var k = 0; k < size && same; k++) {
            same = cells[other * size + k] == cells[r * size + k];
          }
          if (same) return true;
        }
      }
      if (r == size - 1) {
        for (var other = 0; other < c; other++) {
          var same = true;
          for (var k = 0; k < size && same; k++) {
            same = cells[k * size + other] == cells[k * size + c];
          }
          if (same) return true;
        }
      }
      return false;
    }

    bool fill(int i) {
      if (i == cells.length) return true;
      final r = i ~/ size, c = i % size;
      final first = random.nextInt(2);
      for (final v in [first, 1 - first]) {
        if (!ok(i, v)) continue;
        cells[i] = v;
        rowCount[r][v]++;
        colCount[c][v]++;
        if (!duplicatesEarlier(i) && fill(i + 1)) return true;
        rowCount[r][v]--;
        colCount[c][v]--;
        cells[i] = BinaryRules.empty;
      }
      return false;
    }

    if (!fill(0)) throw StateError('Could not fill a binary grid of size $size');
    return cells;
  }

  /// Blanks cells of [solution] in random order, keeping each removal that
  /// leaves the grid solvable by propagation, until [target] givens remain.
  static List<int> carve(List<int> solution, Random random, int size, {required int target}) {
    final givens = List<int>.of(solution, growable: false);
    final order = List<int>.generate(givens.length, (i) => i)..shuffle(random);
    var count = givens.length;
    for (final i in order) {
      if (count <= target) break;
      final v = givens[i];
      givens[i] = BinaryRules.empty;
      if (BinarySolver.solvesByPropagation(givens, size)) {
        count--;
      } else {
        givens[i] = v;
      }
    }
    return givens;
  }
}
