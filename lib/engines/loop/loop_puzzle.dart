import 'loop_grid.dart';
import 'loop_rules.dart';
import 'loop_solver.dart';

/// A validated puzzle: the clues and their unique loop.
///
/// Payload: `{"width": 6, "height": 6, "clues": "36 chars of 0-3 or ."}`.
/// Reveal: `{"edges": {"h": [height + 1 rows of width bits], "v": [height rows of width + 1 bits]}}`;
/// each of `h` and `v` may also be one flat string of the same bits.
class LoopPuzzle {
  /// Validates and copies the inputs. Throws [FormatException] when the
  /// shapes or ranges are wrong, the solution breaks a rule or the clues do
  /// not have exactly one solution.
  factory LoopPuzzle({
    required int width,
    required int height,
    required List<int> clues,
    required List<bool> solution,
  }) {
    final grid = LoopGrid(width, height);
    if (clues.length != grid.cellCount) {
      throw FormatException('Loop clues must have ${grid.cellCount} cells, not ${clues.length}');
    }
    for (var i = 0; i < clues.length; i++) {
      if (clues[i] < -1 || clues[i] > 3) throw FormatException('Loop clue at index $i is out of range: ${clues[i]}');
    }
    if (solution.length != grid.edgeCount) {
      throw FormatException('Loop solution must have ${grid.edgeCount} edges, not ${solution.length}');
    }
    final broken = LoopRules.violation(grid, clues, solution);
    if (broken != null) throw FormatException('Loop reveal does not solve the puzzle: $broken');
    if (LoopSolver.countSolutions(grid, clues) != 1) {
      throw const FormatException('Loop clues do not have a unique solution');
    }
    return LoopPuzzle._(grid, List<int>.unmodifiable(clues), List<bool>.unmodifiable(solution));
  }

  const LoopPuzzle._(this.grid, this.clues, this.solution);

  static LoopPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final width = payload['width'];
    final height = payload['height'];
    if (width is! int || height is! int) throw const FormatException('Loop payload needs integer "width" and "height"');
    final rawClues = payload['clues'];
    if (rawClues is! String) throw const FormatException('Loop payload is missing "clues"');
    final edges = reveal['edges'];
    if (edges is! Map) throw const FormatException('Loop reveal is missing "edges"');
    final grid = LoopGrid(width, height);
    final h = _bits(edges['h'], rows: height + 1, cols: width, field: 'h');
    final v = _bits(edges['v'], rows: height, cols: width + 1, field: 'v');
    return LoopPuzzle(
      width: width,
      height: height,
      clues: parseClues(rawClues, grid.cellCount),
      solution: [...h, ...v],
    );
  }

  /// Clues as ints, -1 for a blank.
  static List<int> parseClues(String text, int count) {
    if (text.length != count) throw FormatException('Loop clues must be $count characters, not ${text.length}');
    return List<int>.generate(count, (i) {
      final ch = text[i];
      if (ch == '.') return -1;
      final n = int.tryParse(ch);
      if (n == null || n < 0 || n > 3) throw FormatException('Loop clue at index $i must be 0-3 or ".", not "$ch"');
      return n;
    }, growable: false);
  }

  static String formatClues(List<int> clues) => clues.map((c) => c < 0 ? '.' : '$c').join();

  static List<bool> _bits(Object? raw, {required int rows, required int cols, required String field}) {
    final String flat;
    if (raw is String) {
      flat = raw;
    } else if (raw is List && raw.length == rows && raw.every((r) => r is String && r.length == cols)) {
      flat = raw.join();
    } else {
      throw FormatException('Loop reveal "$field" must be $rows rows of $cols bits');
    }
    if (flat.length != rows * cols) throw FormatException('Loop reveal "$field" must have ${rows * cols} bits');
    return List<bool>.generate(flat.length, (i) {
      final ch = flat[i];
      if (ch != '0' && ch != '1') throw FormatException('Loop reveal "$field" holds "$ch"; only 0 and 1 are allowed');
      return ch == '1';
    }, growable: false);
  }

  final LoopGrid grid;

  /// One entry per cell, 0–3 or -1 for a blank.
  final List<int> clues;

  /// One entry per edge: true where the loop runs.
  final List<bool> solution;

  int get width => grid.width;
  int get height => grid.height;

  int clueAt(int cell) => clues[cell];
  bool hasClue(int cell) => clues[cell] >= 0;
  int get clueCount => clues.where((c) => c >= 0).length;
  int get lineCount => solution.where((s) => s).length;

  String get cluesString => formatClues(clues);

  List<String> _rows(int from, int rows, int cols) => List.generate(
        rows,
        (r) => List.generate(cols, (c) => solution[from + r * cols + c] ? '1' : '0').join(),
        growable: false,
      );

  Map<String, dynamic> toPayload() => {'width': width, 'height': height, 'clues': cluesString};

  Map<String, dynamic> toReveal() => {
        'edges': {
          'h': _rows(0, height + 1, width),
          'v': _rows(grid.hCount, height, width + 1),
        },
      };
}
