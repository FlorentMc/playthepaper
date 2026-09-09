/// The geometry of one board: its size, which region each cell belongs to
/// and which cells touch. Cells are indexed row-major. Candidate sets are
/// bitmasks with bit `d` set for digit `d`.
class RegionsGrid {
  RegionsGrid._({
    required this.width,
    required this.height,
    required this.regionOf,
    required this.regionCells,
    required this.neighbours,
  });

  /// Validates a layout: dimensions within [minSide]..[maxSide], every cell
  /// in a region numbered 0..n-1, every region connected and at most
  /// [maxRegionSize] cells.
  factory RegionsGrid({required int width, required int height, required List<int> regionOf}) {
    _checkSize(width, height);
    final count = width * height;
    if (regionOf.length != count) {
      throw FormatException('Regions layout must have $count cells, got ${regionOf.length}');
    }
    final regionCount = regionOf.isEmpty ? 0 : regionOf.reduce((a, b) => a > b ? a : b) + 1;
    if (regionCount > letters.length) throw FormatException('Regions layout has too many regions: $regionCount');
    final cells = List.generate(regionCount, (_) => <int>[]);
    for (var i = 0; i < count; i++) {
      final r = regionOf[i];
      if (r < 0 || r >= regionCount) throw FormatException('Regions layout has a bad region index at cell $i');
      cells[r].add(i);
    }
    for (var r = 0; r < regionCount; r++) {
      if (cells[r].isEmpty) throw FormatException('Regions layout skips region $r');
      if (cells[r].length > maxRegionSize) {
        throw FormatException('Region ${letters[r]} has ${cells[r].length} cells; the most allowed is $maxRegionSize');
      }
      if (!_connected(cells[r], width, height, regionOf)) {
        throw FormatException('Region ${letters[r]} is not connected');
      }
    }
    final neighbours = List.generate(count, (i) {
      final row = i ~/ width, col = i % width;
      final out = <int>[];
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          final r = row + dr, c = col + dc;
          if (r < 0 || r >= height || c < 0 || c >= width) continue;
          out.add(r * width + c);
        }
      }
      return List<int>.unmodifiable(out);
    }, growable: false);
    return RegionsGrid._(
      width: width,
      height: height,
      regionOf: List<int>.unmodifiable(regionOf),
      regionCells: List<List<int>>.unmodifiable(cells.map((c) => List<int>.unmodifiable(c))),
      neighbours: List<List<int>>.unmodifiable(neighbours),
    );
  }

  /// Parses a layout string of region letters, numbering regions in order
  /// of first appearance.
  static RegionsGrid parse({required int width, required int height, required String regions}) {
    _checkSize(width, height);
    final count = width * height;
    if (regions.length != count) {
      throw FormatException('Regions layout must be $count characters, got ${regions.length}');
    }
    final index = <String, int>{};
    final regionOf = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final ch = regions[i];
      if (!letters.contains(ch)) throw FormatException('Regions layout has an invalid character "$ch" at index $i');
      regionOf[i] = index.putIfAbsent(ch, () => index.length);
    }
    return RegionsGrid(width: width, height: height, regionOf: regionOf);
  }

  static const int minSide = 2;
  static const int maxSide = 8;
  static const int maxRegionSize = 5;
  static const String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  final int width;
  final int height;

  /// Region index per cell.
  final List<int> regionOf;

  /// Cells of each region, ascending.
  final List<List<int>> regionCells;

  /// The up to eight cells touching each cell, sides and corners.
  final List<List<int>> neighbours;

  int get cellCount => width * height;
  int get regionCount => regionCells.length;
  int rowOf(int cell) => cell ~/ width;
  int colOf(int cell) => cell % width;

  /// The size of the region holding [cell], which is also its highest digit.
  int sizeOf(int cell) => regionCells[regionOf[cell]].length;

  /// The largest region, so the highest digit anywhere on the board.
  int get maxDigit => regionCells.fold(0, (m, c) => c.length > m ? c.length : m);

  bool sameRegion(int a, int b) => regionOf[a] == regionOf[b];

  /// True when [a] and [b] share a side or a corner.
  bool touches(int a, int b) => neighbours[a].contains(b);

  /// The layout as region letters, one per cell.
  String get regionsString => String.fromCharCodes(regionOf.map((r) => letters.codeUnitAt(r)));

  static int bit(int digit) => 1 << digit;

  /// Bits 1..[size] set.
  static int digitsUpTo(int size) => ((1 << (size + 1)) - 1) & ~1;

  static int bitCount(int mask) {
    var n = 0;
    for (var x = mask; x != 0; x &= x - 1) {
      n++;
    }
    return n;
  }

  static int lowestDigit(int mask) => (mask & -mask).bitLength - 1;

  static Iterable<int> digitsOf(int mask) sync* {
    for (var d = 1; d <= maxRegionSize; d++) {
      if (mask & (1 << d) != 0) yield d;
    }
  }

  /// True when every region of N cells holds 1..N exactly once and no two
  /// touching cells hold the same digit.
  bool isValidSolution(List<int> values) {
    if (values.length != cellCount) return false;
    for (final cells in regionCells) {
      var seen = 0;
      for (final i in cells) {
        final v = values[i];
        if (v < 1 || v > cells.length || seen & bit(v) != 0) return false;
        seen |= bit(v);
      }
    }
    for (var i = 0; i < cellCount; i++) {
      for (final j in neighbours[i]) {
        if (j > i && values[i] == values[j]) return false;
      }
    }
    return true;
  }

  /// Cells whose digit breaks a rule right now: repeated within its region,
  /// above its region's size, or equal to a touching digit. Blanks are 0.
  Set<int> violations(List<int> values) {
    final out = <int>{};
    for (final cells in regionCells) {
      for (var a = 0; a < cells.length; a++) {
        final va = values[cells[a]];
        if (va == 0) continue;
        if (va > cells.length) out.add(cells[a]);
        for (var b = a + 1; b < cells.length; b++) {
          if (values[cells[b]] == va) {
            out.add(cells[a]);
            out.add(cells[b]);
          }
        }
      }
    }
    for (var i = 0; i < cellCount; i++) {
      final v = values[i];
      if (v == 0) continue;
      for (final j in neighbours[i]) {
        if (j > i && values[j] == v) {
          out.add(i);
          out.add(j);
        }
      }
    }
    return out;
  }

  /// Parses cell values: digits, with `.` for a blank when [allowBlank].
  List<int> parseCells(String text, {required String field, required bool allowBlank}) {
    if (text.length != cellCount) {
      throw FormatException('Regions $field must be $cellCount characters, got ${text.length}');
    }
    final cells = List<int>.filled(cellCount, 0);
    for (var i = 0; i < cellCount; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x2E && allowBlank) continue;
      if (unit < 0x31 || unit > 0x39) {
        throw FormatException('Regions $field has an invalid character "${text[i]}" at index $i');
      }
      cells[i] = unit - 0x30;
    }
    return cells;
  }

  static String formatCells(List<int> values) =>
      String.fromCharCodes(values.map((v) => v == 0 ? 0x2E : 0x30 + v));

  static void _checkSize(int width, int height) {
    if (width < minSide || width > maxSide || height < minSide || height > maxSide) {
      throw FormatException('Regions board must be $minSide to $maxSide cells a side, got $width×$height');
    }
  }

  static bool _connected(List<int> cells, int width, int height, List<int> regionOf) {
    final region = regionOf[cells.first];
    final seen = <int>{cells.first};
    final stack = <int>[cells.first];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final row = i ~/ width, col = i % width;
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final r = row + dr, c = col + dc;
        if (r < 0 || r >= height || c < 0 || c >= width) continue;
        final j = r * width + c;
        if (regionOf[j] == region && seen.add(j)) stack.add(j);
      }
    }
    return seen.length == cells.length;
  }
}
