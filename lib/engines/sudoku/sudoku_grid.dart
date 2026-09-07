/// Fixed geometry of a 9×9 grid. Cells are indexed row-major, 0–80.
/// Candidate sets are bitmasks with bit `d` set for digit `d` (1–9).
class SudokuGrid {
  SudokuGrid._();

  static const int cellCount = 81;
  static const int allDigits = 0x3FE;

  static final List<int> rowOf = List.generate(cellCount, (i) => i ~/ 9, growable: false);
  static final List<int> colOf = List.generate(cellCount, (i) => i % 9, growable: false);
  static final List<int> boxOf = List.generate(cellCount, (i) => (i ~/ 27) * 3 + (i % 9) ~/ 3, growable: false);

  static final List<List<int>> rows = List.generate(9, (r) => List.generate(9, (c) => r * 9 + c, growable: false));
  static final List<List<int>> cols = List.generate(9, (c) => List.generate(9, (r) => r * 9 + c, growable: false));
  static final List<List<int>> boxes = List.generate(
    9,
    (b) => List.generate(9, (k) => ((b ~/ 3) * 3 + k ~/ 3) * 9 + (b % 3) * 3 + k % 3, growable: false),
  );

  /// Rows, then columns, then boxes.
  static final List<List<int>> units = [...rows, ...cols, ...boxes];

  /// The 20 cells sharing a row, column or box with each cell.
  static final List<List<int>> peers = List.generate(cellCount, (i) {
    final set = <int>{...rows[rowOf[i]], ...cols[colOf[i]], ...boxes[boxOf[i]]}..remove(i);
    return set.toList(growable: false)..sort();
  }, growable: false);

  static final List<int> _popcount = List.generate(1024, (m) {
    var n = 0;
    for (var x = m; x != 0; x &= x - 1) {
      n++;
    }
    return n;
  }, growable: false);

  static int bit(int digit) => 1 << digit;

  static int bitCount(int mask) => _popcount[mask & 0x3FF];

  /// The digit of a single-bit mask.
  static int lowestDigit(int mask) => (mask & -mask).bitLength - 1;

  static Iterable<int> digitsOf(int mask) sync* {
    for (var d = 1; d <= 9; d++) {
      if (mask & (1 << d) != 0) yield d;
    }
  }

  /// True when every row, column and box holds the digits 1–9 exactly once.
  static bool isValidSolution(List<int> grid) {
    if (grid.length != cellCount) return false;
    for (final unit in units) {
      var seen = 0;
      for (final i in unit) {
        final v = grid[i];
        if (v < 1 || v > 9 || seen & (1 << v) != 0) return false;
        seen |= 1 << v;
      }
    }
    return true;
  }

  /// Parses 81 digit characters into cell values. Blanks are `0`.
  static List<int> parseCells(String text, {required String field, required bool allowBlank}) {
    if (text.length != cellCount) {
      throw FormatException('Sudoku $field must be $cellCount characters, got ${text.length}');
    }
    final low = allowBlank ? 0x30 : 0x31;
    final cells = List<int>.filled(cellCount, 0);
    for (var i = 0; i < cellCount; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < low || unit > 0x39) {
        throw FormatException('Sudoku $field has an invalid character "${text[i]}" at index $i');
      }
      cells[i] = unit - 0x30;
    }
    return cells;
  }

  static String formatCells(List<int> cells) => cells.join();
}
