import 'dart:math';

import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'bridges_layout.dart';
import 'bridges_puzzle.dart';
import 'bridges_solver.dart';

/// Deterministic daily puzzles: the same date always gives the same board.
///
/// A board grows from one island: a random island sprouts a bridge in a
/// random direction to a fresh cell, until the target number of islands is
/// placed, then a few extra bridges join islands that already face each
/// other so the network has loops. The counts are read off, and the board
/// is kept only when the solver proves the solution unique and rates the
/// puzzle [BridgesRating.medium]: solvable by reasoning alone, but not by
/// counting alone.
class BridgesGenerator {
  BridgesGenerator();

  static const int width = 7;
  static const int height = 7;
  static const int minIslands = 12;
  static const int maxIslands = 16;
  static const int maxAttempts = 2000;

  static int seedFor(String date) => fnv1a('bridges-$date');

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
    final id = PuzzleId(game: GameKind.bridges, date: date);
    final puzzle = generatePuzzle(seed: seedFor(id.dateString));
    return PuzzleRecord(
      id: id,
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
  }

  /// The first board from [seed] that is unique, has [minIslands] to
  /// [maxIslands] islands and is rated [rating].
  static BridgesPuzzle generatePuzzle({
    required int seed,
    int width = BridgesGenerator.width,
    int height = BridgesGenerator.height,
    int minIslands = BridgesGenerator.minIslands,
    int maxIslands = BridgesGenerator.maxIslands,
    BridgesRating rating = BridgesRating.medium,
  }) {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final random = Random(_derive(seed, attempt));
      final grown = grow(random, width: width, height: height, minIslands: minIslands, maxIslands: maxIslands);
      if (grown == null) continue;
      final layout = BridgesLayout(width: width, height: height, islands: grown.islands);
      if (BridgesSolver.countSolutions(layout) != 1 || BridgesSolver.rate(layout) != rating) continue;
      return BridgesPuzzle(layout: layout, solution: grown.solutionFor(layout));
    }
    throw StateError('No bridges puzzle found for seed $seed in $maxAttempts attempts');
  }

  static int _derive(int seed, int attempt) => (seed & 0xFFFFFFFF) ^ ((attempt * 0x9E3779B1) & 0xFFFFFFFF);

  /// Grows one candidate board. Null when the board could not reach
  /// [minIslands] islands.
  static GrownBoard? grow(
    Random random, {
    required int width,
    required int height,
    required int minIslands,
    required int maxIslands,
  }) {
    final cells = List<_Cell>.filled(width * height, _Cell.empty);
    final islands = <BridgesIsland>[];
    final links = <List<int>>[];
    final target = minIslands + random.nextInt(maxIslands - minIslands + 1);

    bool nearIsland(int r, int c) =>
        _isIsland(cells, width, height, r - 1, c) ||
        _isIsland(cells, width, height, r + 1, c) ||
        _isIsland(cells, width, height, r, c - 1) ||
        _isIsland(cells, width, height, r, c + 1);

    void place(int r, int c) {
      cells[r * width + c] = _Cell.island;
      islands.add(BridgesIsland(row: r, col: c, count: 0));
    }

    void link(int a, int b, int count) {
      final ia = islands[a], ib = islands[b];
      final horizontal = ia.row == ib.row;
      final from = horizontal ? min(ia.col, ib.col) : min(ia.row, ib.row);
      final to = horizontal ? max(ia.col, ib.col) : max(ia.row, ib.row);
      for (var k = from + 1; k < to; k++) {
        cells[horizontal ? ia.row * width + k : k * width + ia.col] = _Cell.bridge;
      }
      links.add([a, b, count]);
    }

    place(random.nextInt(height), random.nextInt(width));
    var stalls = 0;
    while (islands.length < target && stalls < 60) {
      final a = random.nextInt(islands.length);
      final dir = _directions[random.nextInt(4)];
      final spots = <int>[];
      for (var d = 1;; d++) {
        final r = islands[a].row + dir[0] * d, c = islands[a].col + dir[1] * d;
        if (r < 0 || r >= height || c < 0 || c >= width || cells[r * width + c] != _Cell.empty) break;
        if (d >= 2 && !nearIsland(r, c)) spots.add(d);
      }
      if (spots.isEmpty) {
        stalls++;
        continue;
      }
      final d = spots[random.nextInt(spots.length)];
      place(islands[a].row + dir[0] * d, islands[a].col + dir[1] * d);
      link(a, islands.length - 1, random.nextInt(100) < doublePercent ? 2 : 1);
      stalls = 0;
    }
    if (islands.length < minIslands) return null;

    for (var a = 0; a < islands.length; a++) {
      for (var b = a + 1; b < islands.length; b++) {
        if (random.nextInt(100) >= extraLinkPercent) continue;
        final ia = islands[a], ib = islands[b];
        if (ia.row != ib.row && ia.col != ib.col) continue;
        if (links.any((l) => (l[0] == a && l[1] == b) || (l[0] == b && l[1] == a))) continue;
        final horizontal = ia.row == ib.row;
        final from = horizontal ? min(ia.col, ib.col) : min(ia.row, ib.row);
        final to = horizontal ? max(ia.col, ib.col) : max(ia.row, ib.row);
        var clear = true;
        for (var k = from + 1; k < to && clear; k++) {
          clear = cells[horizontal ? ia.row * width + k : k * width + ia.col] == _Cell.empty;
        }
        if (clear) link(a, b, random.nextInt(100) < doublePercent ? 2 : 1);
      }
    }

    final counts = List<int>.filled(islands.length, 0);
    for (final l in links) {
      counts[l[0]] += l[2];
      counts[l[1]] += l[2];
    }
    return GrownBoard(
      islands: [
        for (var i = 0; i < islands.length; i++)
          BridgesIsland(row: islands[i].row, col: islands[i].col, count: counts[i]),
      ],
      links: links,
    );
  }

  static const int doublePercent = 35;
  static const int extraLinkPercent = 30;

  static const List<List<int>> _directions = [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
  ];

  static bool _isIsland(List<_Cell> cells, int width, int height, int r, int c) =>
      r >= 0 && r < height && c >= 0 && c < width && cells[r * width + c] == _Cell.island;
}

enum _Cell { empty, island, bridge }

/// A grown board: islands with their counts, and the bridges that produced
/// them as `[a, b, count]`.
class GrownBoard {
  const GrownBoard({required this.islands, required this.links});

  final List<BridgesIsland> islands;
  final List<List<int>> links;

  List<int> solutionFor(BridgesLayout layout) {
    final solution = List<int>.filled(layout.pairs.length, 0);
    for (final l in links) {
      solution[layout.pairBetween(l[0], l[1])!] = l[2];
    }
    return solution;
  }
}
