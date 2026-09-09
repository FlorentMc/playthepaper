import 'nonogram_line.dart';
import 'nonogram_solver.dart';

/// A validated nonogram: the row and column clues, the picture they describe
/// and its title.
///
/// Payload: `{"width": 10, "height": 10, "rows": [[2, 1], ...], "cols": [[...], ...], "title": "Teapot"}`.
/// Reveal: `{"cells": ["0110100110", ...]}`, one string per row, `1` for a filled cell.
class NonogramPuzzle {
  /// Validates the clues against the picture and proves the clues have no
  /// other solution. Throws [FormatException] otherwise.
  factory NonogramPuzzle({
    required int width,
    required int height,
    required List<List<int>> rows,
    required List<List<int>> cols,
    required String title,
    required List<int> rowMasks,
  }) {
    _checkSize(width, 'width');
    _checkSize(height, 'height');
    if (rows.length != height) throw FormatException('Nonogram needs $height row clues, got ${rows.length}');
    if (cols.length != width) throw FormatException('Nonogram needs $width column clues, got ${cols.length}');
    for (var r = 0; r < height; r++) {
      _checkClue(rows[r], width, 'row ${r + 1}');
    }
    for (var c = 0; c < width; c++) {
      _checkClue(cols[c], height, 'column ${c + 1}');
    }
    if (rowMasks.length != height) throw FormatException('Nonogram picture needs $height rows, got ${rowMasks.length}');
    final all = (1 << width) - 1;
    for (var r = 0; r < height; r++) {
      if (rowMasks[r] < 0 || rowMasks[r] & ~all != 0) throw FormatException('Nonogram picture row ${r + 1} is out of range');
    }
    if (title.trim().isEmpty || title.length > maxTitleLength) {
      throw const FormatException('Nonogram title must be 1 to $maxTitleLength characters');
    }
    for (var r = 0; r < height; r++) {
      final got = NonogramLine.runs(rowMasks[r], width);
      if (!_sameClue(got, rows[r])) throw FormatException('Nonogram row ${r + 1} clue ${rows[r]} does not match the picture $got');
    }
    for (var c = 0; c < width; c++) {
      final got = NonogramLine.runs(_column(rowMasks, c), height);
      if (!_sameClue(got, cols[c])) throw FormatException('Nonogram column ${c + 1} clue ${cols[c]} does not match the picture $got');
    }
    final puzzle = NonogramPuzzle._(
      width: width,
      height: height,
      rows: List.unmodifiable(rows.map((c) => List<int>.unmodifiable(c))),
      cols: List.unmodifiable(cols.map((c) => List<int>.unmodifiable(c))),
      title: title.trim(),
      rowMasks: List<int>.unmodifiable(rowMasks),
    );
    if (NonogramSolver.countSolutions(puzzle) != 1) {
      throw const FormatException('Nonogram clues do not have a unique solution');
    }
    return puzzle;
  }

  const NonogramPuzzle._({
    required this.width,
    required this.height,
    required this.rows,
    required this.cols,
    required this.title,
    required this.rowMasks,
  });

  static const int minSize = 3;
  static const int maxSize = 20;
  static const int maxTitleLength = 40;

  /// Derives the clues from a picture given as strings of `0` and `1`.
  factory NonogramPuzzle.fromPicture({required List<String> picture, required String title}) {
    final height = picture.length;
    _checkSize(height, 'height');
    final width = picture.first.length;
    _checkSize(width, 'width');
    final rowMasks = List<int>.generate(height, (r) => parseRow(picture[r], width, 'row ${r + 1}'));
    return NonogramPuzzle(
      width: width,
      height: height,
      rows: List.generate(height, (r) => NonogramLine.runs(rowMasks[r], width)),
      cols: List.generate(width, (c) => NonogramLine.runs(_column(rowMasks, c), height)),
      title: title,
      rowMasks: rowMasks,
    );
  }

  static NonogramPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final width = payload['width'];
    final height = payload['height'];
    if (width is! int) throw const FormatException('Nonogram payload is missing "width"');
    if (height is! int) throw const FormatException('Nonogram payload is missing "height"');
    _checkSize(width, 'width');
    _checkSize(height, 'height');
    final title = payload['title'];
    if (title is! String) throw const FormatException('Nonogram payload is missing "title"');
    final cells = reveal['cells'];
    if (cells is! List) throw const FormatException('Nonogram reveal is missing "cells"');
    if (cells.length != height) throw FormatException('Nonogram reveal needs $height rows, got ${cells.length}');
    final rowMasks = <int>[];
    for (var r = 0; r < height; r++) {
      final row = cells[r];
      if (row is! String) throw FormatException('Nonogram reveal row ${r + 1} must be a string');
      rowMasks.add(parseRow(row, width, 'row ${r + 1}'));
    }
    return NonogramPuzzle(
      width: width,
      height: height,
      rows: _clues(payload['rows'], height, 'rows'),
      cols: _clues(payload['cols'], width, 'cols'),
      title: title,
      rowMasks: rowMasks,
    );
  }

  final int width;
  final int height;

  /// Run lengths per row, top to bottom; an empty list for a blank row.
  final List<List<int>> rows;

  /// Run lengths per column, left to right.
  final List<List<int>> cols;
  final String title;

  /// The picture, one bitmask per row with bit `c` set when column `c` is filled.
  final List<int> rowMasks;

  int get cellCount => width * height;

  bool filledAt(int row, int col) => rowMasks[row] & (1 << col) != 0;

  bool isFilled(int index) => filledAt(index ~/ width, index % width);

  int get filledCount {
    var n = 0;
    for (var i = 0; i < cellCount; i++) {
      if (isFilled(i)) n++;
    }
    return n;
  }

  double get fillFraction => filledCount / cellCount;

  int columnMask(int col) => _column(rowMasks, col);

  List<String> get picture => List.generate(height, (r) => formatRow(rowMasks[r], width));

  Map<String, dynamic> toPayload() => {
        'width': width,
        'height': height,
        'rows': rows.map((c) => List<int>.of(c)).toList(),
        'cols': cols.map((c) => List<int>.of(c)).toList(),
        'title': title,
      };

  Map<String, dynamic> toReveal() => {'cells': picture};

  static int parseRow(String text, int width, String where) {
    if (text.length != width) throw FormatException('Nonogram $where must be $width characters, got ${text.length}');
    var mask = 0;
    for (var c = 0; c < width; c++) {
      switch (text[c]) {
        case '1':
          mask |= 1 << c;
        case '0':
          break;
        default:
          throw FormatException('Nonogram $where has "${text[c]}"; only 0 and 1 are allowed');
      }
    }
    return mask;
  }

  static String formatRow(int mask, int width) {
    final buffer = StringBuffer();
    for (var c = 0; c < width; c++) {
      buffer.write(mask & (1 << c) != 0 ? '1' : '0');
    }
    return buffer.toString();
  }

  static int _column(List<int> rowMasks, int col) {
    var mask = 0;
    for (var r = 0; r < rowMasks.length; r++) {
      if (rowMasks[r] & (1 << col) != 0) mask |= 1 << r;
    }
    return mask;
  }

  static void _checkSize(int size, String field) {
    if (size < minSize || size > maxSize) {
      throw FormatException('Nonogram $field must be between $minSize and $maxSize, got $size');
    }
  }

  static void _checkClue(List<int> clue, int length, String where) {
    for (final run in clue) {
      if (run < 1) throw FormatException('Nonogram $where clue has a run of $run');
    }
    if (NonogramLine.minLength(clue) > length) {
      throw FormatException('Nonogram $where clue $clue does not fit in $length cells');
    }
  }

  static List<List<int>> _clues(Object? raw, int count, String field) {
    if (raw is! List) throw FormatException('Nonogram payload is missing "$field"');
    if (raw.length != count) throw FormatException('Nonogram "$field" needs $count clues, got ${raw.length}');
    return [
      for (final clue in raw)
        if (clue is List && clue.every((v) => v is int))
          clue.cast<int>()
        else
          throw FormatException('Nonogram "$field" clues must be lists of ints'),
    ];
  }

  static bool _sameClue(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
