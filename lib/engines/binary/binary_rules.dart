/// Geometry and rules of a Takuzu grid. Cells are indexed row-major and hold
/// [empty], 0 or 1. Every rule is checked here, both for a partial grid
/// (live conflicts) and for a complete one (a solution).
class BinaryRules {
  BinaryRules._();

  static const int empty = -1;
  static const int minSize = 4;
  static const int maxSize = 16;

  static void checkSize(int size) {
    if (size < minSize || size > maxSize || size.isOdd) {
      throw FormatException('Binary size must be even and between $minSize and $maxSize, got $size');
    }
  }

  static final Map<int, List<List<int>>> _lines = {};

  /// Rows then columns, each as a list of cell indices.
  static List<List<int>> lines(int size) => _lines.putIfAbsent(size, () {
        final rows = List.generate(size, (r) => List.generate(size, (c) => r * size + c, growable: false));
        final cols = List.generate(size, (c) => List.generate(size, (r) => r * size + c, growable: false));
        return List.unmodifiable([...rows, ...cols]);
      });

  static List<List<int>> rows(int size) => lines(size).sublist(0, size);
  static List<List<int>> cols(int size) => lines(size).sublist(size);

  /// Parses `size × size` characters of `0`, `1` and, when allowed, `.`.
  static List<int> parseCells(String text, int size, {required String field, required bool allowBlank}) {
    final count = size * size;
    if (text.length != count) {
      throw FormatException('Binary $field must be $count characters for size $size, got ${text.length}');
    }
    final cells = List<int>.filled(count, empty);
    for (var i = 0; i < count; i++) {
      final ch = text[i];
      if (ch == '0') {
        cells[i] = 0;
      } else if (ch == '1') {
        cells[i] = 1;
      } else if (ch == '.' && allowBlank) {
        cells[i] = empty;
      } else {
        throw FormatException('Binary $field has an invalid character "$ch" at index $i');
      }
    }
    return cells;
  }

  static String formatCells(List<int> cells) => cells.map((v) => v == empty ? '.' : '$v').join();

  static bool isComplete(List<int> grid) => !grid.contains(empty);

  /// Cells inside a run of three equal symbols.
  static Set<int> tripleCells(List<int> grid, int size) {
    final out = <int>{};
    for (final line in lines(size)) {
      for (var k = 0; k + 2 < size; k++) {
        final v = grid[line[k]];
        if (v != empty && grid[line[k + 1]] == v && grid[line[k + 2]] == v) {
          out.addAll([line[k], line[k + 1], line[k + 2]]);
        }
      }
    }
    return out;
  }

  /// Cells carrying a symbol that already appears more than `size / 2` times
  /// in their row or column.
  static Set<int> overCountCells(List<int> grid, int size) {
    final out = <int>{};
    final half = size ~/ 2;
    for (final line in lines(size)) {
      for (final v in const [0, 1]) {
        final cells = line.where((i) => grid[i] == v).toList();
        if (cells.length > half) out.addAll(cells);
      }
    }
    return out;
  }

  /// Cells of complete rows (or columns) that repeat another complete row
  /// (or column).
  static Set<int> duplicateLineCells(List<int> grid, int size) {
    final out = <int>{};
    for (final group in [rows(size), cols(size)]) {
      final complete = group.where((line) => line.every((i) => grid[i] != empty)).toList();
      for (var a = 0; a < complete.length; a++) {
        for (var b = a + 1; b < complete.length; b++) {
          if (_sameLine(grid, complete[a], complete[b])) {
            out.addAll(complete[a]);
            out.addAll(complete[b]);
          }
        }
      }
    }
    return out;
  }

  static bool _sameLine(List<int> grid, List<int> a, List<int> b) {
    for (var k = 0; k < a.length; k++) {
      if (grid[a[k]] != grid[b[k]]) return false;
    }
    return true;
  }

  /// Every cell that breaks a rule in the grid as it stands.
  static Set<int> violations(List<int> grid, int size) =>
      {...tripleCells(grid, size), ...overCountCells(grid, size), ...duplicateLineCells(grid, size)};

  /// True when every cell holds 0 or 1, each row and column has equal counts,
  /// no three equal symbols touch, and no two rows or columns are the same.
  static bool isValidSolution(List<int> grid, int size) {
    if (grid.length != size * size) return false;
    if (grid.any((v) => v != 0 && v != 1)) return false;
    return violations(grid, size).isEmpty;
  }
}
