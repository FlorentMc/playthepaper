/// The board geometry of a kakuro: blocks, clue cells and white cells, with
/// the runs the clues define. Cells are indexed row-major.
///
/// Payload: `{"width": 6, "height": 6, "cells": ["#", {"down": 16, "across": null}, ".", ...]}`.
/// Candidate sets are bitmasks with bit `d` set for digit `d` (1–9).
enum KakuroCellKind { block, clue, white }

class KakuroCell {
  const KakuroCell.block()
      : kind = KakuroCellKind.block,
        down = null,
        across = null;

  const KakuroCell.white()
      : kind = KakuroCellKind.white,
        down = null,
        across = null;

  const KakuroCell.clue({this.down, this.across}) : kind = KakuroCellKind.clue;

  final KakuroCellKind kind;

  /// The sum of the run below this clue, or null when there is none.
  final int? down;

  /// The sum of the run to the right of this clue, or null when there is none.
  final int? across;

  bool get isWhite => kind == KakuroCellKind.white;
  bool get isClue => kind == KakuroCellKind.clue;
  bool get isBlock => kind == KakuroCellKind.block;

  Object toJson() => switch (kind) {
        KakuroCellKind.block => '#',
        KakuroCellKind.white => '.',
        KakuroCellKind.clue => {'down': down, 'across': across},
      };

  static KakuroCell fromJson(Object? raw, int index) {
    if (raw == '#') return const KakuroCell.block();
    if (raw == '.') return const KakuroCell.white();
    if (raw is Map) {
      final down = _clueValue(raw['down'], 'down', index);
      final across = _clueValue(raw['across'], 'across', index);
      if (down == null && across == null) {
        throw FormatException('Kakuro clue at index $index has neither a down nor an across sum');
      }
      return KakuroCell.clue(down: down, across: across);
    }
    throw FormatException('Kakuro cell at index $index must be "#", "." or a clue object');
  }

  static int? _clueValue(Object? raw, String field, int index) {
    if (raw == null) return null;
    if (raw is! int || raw < KakuroGrid.minSum(1) || raw > KakuroGrid.maxSum(9)) {
      throw FormatException('Kakuro clue "$field" at index $index must be null or an int from 1 to 45');
    }
    return raw;
  }
}

/// One maximal line of white cells headed by a clue.
class KakuroRun {
  const KakuroRun({
    required this.index,
    required this.clueCell,
    required this.cells,
    required this.sum,
    required this.isAcross,
  });

  final int index;
  final int clueCell;
  final List<int> cells;
  final int sum;
  final bool isAcross;

  int get length => cells.length;
  String get direction => isAcross ? 'across' : 'down';
}

class KakuroGrid {
  KakuroGrid._({
    required this.width,
    required this.height,
    required this.cells,
    required this.runs,
    required this.acrossRunOf,
    required this.downRunOf,
    required this.whiteCells,
  });

  /// Validates the geometry: dimensions, cell shapes, every clue heading a run
  /// of two to nine cells with a feasible sum, and every white cell lying in
  /// exactly one across and one down run. Throws [FormatException] otherwise.
  factory KakuroGrid({required int width, required int height, required List<KakuroCell> cells}) {
    if (width < minSize || width > maxSize || height < minSize || height > maxSize) {
      throw FormatException('Kakuro width and height must be between $minSize and $maxSize, got $width×$height');
    }
    if (cells.length != width * height) {
      throw FormatException('Kakuro cells must have ${width * height} entries, got ${cells.length}');
    }
    final acrossRunOf = List<int>.filled(cells.length, -1);
    final downRunOf = List<int>.filled(cells.length, -1);
    final runs = <KakuroRun>[];
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (!cell.isClue) continue;
      final r = i ~/ width, c = i % width;
      if (cell.across != null) {
        final line = <int>[];
        for (var k = c + 1; k < width && cells[r * width + k].isWhite; k++) {
          line.add(r * width + k);
        }
        runs.add(_run(runs.length, i, line, cell.across!, isAcross: true, row: r, col: c));
        for (final w in line) {
          acrossRunOf[w] = runs.last.index;
        }
      }
      if (cell.down != null) {
        final line = <int>[];
        for (var k = r + 1; k < height && cells[k * width + c].isWhite; k++) {
          line.add(k * width + c);
        }
        runs.add(_run(runs.length, i, line, cell.down!, isAcross: false, row: r, col: c));
        for (final w in line) {
          downRunOf[w] = runs.last.index;
        }
      }
    }
    final whiteCells = <int>[];
    for (var i = 0; i < cells.length; i++) {
      if (!cells[i].isWhite) continue;
      whiteCells.add(i);
      if (acrossRunOf[i] < 0) {
        throw FormatException('Kakuro white cell at row ${i ~/ width + 1}, column ${i % width + 1} has no across clue');
      }
      if (downRunOf[i] < 0) {
        throw FormatException('Kakuro white cell at row ${i ~/ width + 1}, column ${i % width + 1} has no down clue');
      }
    }
    if (whiteCells.isEmpty) throw const FormatException('Kakuro grid has no white cells');
    return KakuroGrid._(
      width: width,
      height: height,
      cells: List<KakuroCell>.unmodifiable(cells),
      runs: List<KakuroRun>.unmodifiable(runs),
      acrossRunOf: List<int>.unmodifiable(acrossRunOf),
      downRunOf: List<int>.unmodifiable(downRunOf),
      whiteCells: List<int>.unmodifiable(whiteCells),
    );
  }

  static KakuroRun _run(
    int index,
    int clueCell,
    List<int> line,
    int sum, {
    required bool isAcross,
    required int row,
    required int col,
  }) {
    final where = '${isAcross ? 'across' : 'down'} clue at row ${row + 1}, column ${col + 1}';
    if (line.length < minRunLength || line.length > maxRunLength) {
      throw FormatException('Kakuro $where must cover $minRunLength to $maxRunLength white cells, covers ${line.length}');
    }
    if (sum < minSum(line.length) || sum > maxSum(line.length)) {
      throw FormatException('Kakuro $where: $sum cannot be made with ${line.length} different digits');
    }
    return KakuroRun(
      index: index,
      clueCell: clueCell,
      cells: List<int>.unmodifiable(line),
      sum: sum,
      isAcross: isAcross,
    );
  }

  static KakuroGrid parsePayload(Map<String, dynamic> payload) {
    final width = payload['width'];
    final height = payload['height'];
    if (width is! int || height is! int) throw const FormatException('Kakuro payload needs int "width" and "height"');
    final rawCells = payload['cells'];
    if (rawCells is! List) throw const FormatException('Kakuro payload is missing "cells"');
    final cells = <KakuroCell>[];
    for (var i = 0; i < rawCells.length; i++) {
      cells.add(KakuroCell.fromJson(rawCells[i], i));
    }
    return KakuroGrid(width: width, height: height, cells: cells);
  }

  static const int minSize = 2;
  static const int maxSize = 12;
  static const int minRunLength = 2;
  static const int maxRunLength = 9;
  static const int allDigits = 0x3FE;

  /// The smallest sum of [n] different digits.
  static int minSum(int n) => n * (n + 1) ~/ 2;

  /// The largest sum of [n] different digits.
  static int maxSum(int n) => n * (19 - n) ~/ 2;

  static int bit(int digit) => 1 << digit;

  static int bitCount(int mask) {
    var n = 0;
    for (var x = mask; x != 0; x &= x - 1) {
      n++;
    }
    return n;
  }

  static Iterable<int> digitsOf(int mask) sync* {
    for (var d = 1; d <= 9; d++) {
      if (mask & (1 << d) != 0) yield d;
    }
  }

  final int width;
  final int height;
  final List<KakuroCell> cells;
  final List<KakuroRun> runs;

  /// Run index per cell, -1 for cells that are not white.
  final List<int> acrossRunOf;
  final List<int> downRunOf;
  final List<int> whiteCells;

  int get cellCount => cells.length;
  int get whiteCount => whiteCells.length;

  int indexOf(int row, int col) => row * width + col;
  int rowOf(int index) => index ~/ width;
  int colOf(int index) => index % width;

  KakuroCell cellAt(int index) => cells[index];
  bool isWhite(int index) => cells[index].isWhite;

  /// The across and down runs through a white cell.
  List<KakuroRun> runsThrough(int index) {
    if (!isWhite(index)) return const [];
    return [runs[acrossRunOf[index]], runs[downRunOf[index]]];
  }

  /// Why [values] (one int per cell, 0 for empty) do not solve this grid, or
  /// null when they do: every white cell filled with a digit, no digit
  /// repeated within a run, every run summing to its clue.
  String? firstViolation(List<int> values) {
    if (values.length != cellCount) return 'Kakuro values must have $cellCount entries';
    for (final i in whiteCells) {
      final v = values[i];
      if (v < 1 || v > 9) return 'Kakuro cell at row ${rowOf(i) + 1}, column ${colOf(i) + 1} is not a digit from 1 to 9';
    }
    for (final run in runs) {
      var seen = 0;
      var total = 0;
      for (final c in run.cells) {
        final b = bit(values[c]);
        if (seen & b != 0) return 'Kakuro ${_describe(run)} repeats the digit ${values[c]}';
        seen |= b;
        total += values[c];
      }
      if (total != run.sum) return 'Kakuro ${_describe(run)} sums to $total, not ${run.sum}';
    }
    return null;
  }

  bool isSolvedBy(List<int> values) => firstViolation(values) == null;

  /// Cells holding a digit that appears twice in one of their runs.
  Set<int> conflicts(List<int> values) {
    final result = <int>{};
    for (final run in runs) {
      for (var a = 0; a < run.length; a++) {
        final va = values[run.cells[a]];
        if (va == 0) continue;
        for (var b = a + 1; b < run.length; b++) {
          if (values[run.cells[b]] == va) {
            result.add(run.cells[a]);
            result.add(run.cells[b]);
          }
        }
      }
    }
    return result;
  }

  String _describe(KakuroRun run) =>
      '${run.direction} run of ${run.sum} at row ${rowOf(run.clueCell) + 1}, column ${colOf(run.clueCell) + 1}';

  Map<String, dynamic> toPayload() => {
        'width': width,
        'height': height,
        'cells': cells.map((c) => c.toJson()).toList(),
      };
}
