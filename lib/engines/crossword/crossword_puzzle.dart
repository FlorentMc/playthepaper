import 'package:equatable/equatable.dart';

/// Reading direction of a crossword entry.
enum Direction {
  across('Across'),
  down('Down');

  const Direction(this.label);
  final String label;

  Direction get other => this == across ? down : across;
}

/// One numbered entry: a maximal run of letter cells in one direction.
/// [cells] are row-major grid indices, in reading order.
class CrosswordEntry extends Equatable {
  CrosswordEntry({
    required this.number,
    required this.row,
    required this.col,
    required this.length,
    required this.direction,
    required int size,
    this.clue = '',
  }) : cells = List.unmodifiable([
          for (var i = 0; i < length; i++)
            direction == Direction.across ? row * size + col + i : (row + i) * size + col,
        ]);

  const CrosswordEntry._({
    required this.number,
    required this.row,
    required this.col,
    required this.length,
    required this.direction,
    required this.cells,
    required this.clue,
  });

  final int number;
  final int row;
  final int col;
  final int length;
  final Direction direction;
  final List<int> cells;
  final String clue;

  /// `3 Across`.
  String get label => '$number ${direction.label}';

  CrosswordEntry withClue(String clue) => CrosswordEntry._(
        number: number,
        row: row,
        col: col,
        length: length,
        direction: direction,
        cells: cells,
        clue: clue,
      );

  Map<String, dynamic> toJson() => {
        'number': number,
        'row': row,
        'col': col,
        'length': length,
        'clue': clue,
      };

  @override
  List<Object?> get props => [number, row, col, length, direction, clue];
}

const String blockChar = '#';
const String letterChar = '.';

/// Computes standard crossword numbering for a square grid of `.` (letter)
/// and `#` (block) rows. Scans row-major; a cell takes the next number when
/// it starts an across run (block or edge to its left, letter to its right)
/// or a down run (block or edge above, letter below). Runs are maximal.
///
/// Throws [FormatException] when the grid is not square, contains other
/// characters, has a run of exactly two letters, or has a letter cell that
/// belongs to no entry.
List<CrosswordEntry> deriveEntries(List<String> grid) {
  final size = grid.length;
  if (size < 3) throw FormatException('Grid must have at least 3 rows, found $size');
  for (var r = 0; r < size; r++) {
    final row = grid[r];
    if (row.length != size) {
      throw FormatException('Grid row ${r + 1} has ${row.length} cells, expected $size');
    }
    if (!RegExp(r'^[.#]+$').hasMatch(row)) {
      throw FormatException('Grid row ${r + 1} may only contain "." and "#": $row');
    }
  }

  bool isLetter(int r, int c) => r >= 0 && r < size && c >= 0 && c < size && grid[r][c] == letterChar;

  final entries = <CrosswordEntry>[];
  final covered = List<bool>.filled(size * size, false);
  var number = 0;
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      if (!isLetter(r, c)) continue;
      final startsAcross = !isLetter(r, c - 1) && isLetter(r, c + 1);
      final startsDown = !isLetter(r - 1, c) && isLetter(r + 1, c);
      if (!startsAcross && !startsDown) continue;
      number++;
      if (startsAcross) {
        var length = 0;
        while (isLetter(r, c + length)) {
          length++;
        }
        entries.add(CrosswordEntry(number: number, row: r, col: c, length: length, direction: Direction.across, size: size));
      }
      if (startsDown) {
        var length = 0;
        while (isLetter(r + length, c)) {
          length++;
        }
        entries.add(CrosswordEntry(number: number, row: r, col: c, length: length, direction: Direction.down, size: size));
      }
    }
  }

  for (final e in entries) {
    if (e.length < 3) {
      throw FormatException(
        '${e.label} at row ${e.row + 1} column ${e.col + 1} is only ${e.length} letters long; entries must be at least 3',
      );
    }
    for (final cell in e.cells) {
      covered[cell] = true;
    }
  }
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      if (isLetter(r, c) && !covered[r * size + c]) {
        throw FormatException('Letter cell at row ${r + 1} column ${c + 1} belongs to no entry');
      }
    }
  }
  return entries;
}

/// A parsed, validated crossword: grid, numbered and clued entries, and the
/// solution. Entries are ordered across by number, then down by number.
class CrosswordPuzzle {
  CrosswordPuzzle._({
    required this.size,
    required this.grid,
    required this.solution,
    required this.entries,
  })  : _acrossAt = List<CrosswordEntry?>.filled(size * size, null),
        _downAt = List<CrosswordEntry?>.filled(size * size, null),
        _numberAt = List<int?>.filled(size * size, null) {
    for (final e in entries) {
      final slots = e.direction == Direction.across ? _acrossAt : _downAt;
      for (final cell in e.cells) {
        slots[cell] = e;
      }
      _numberAt[e.cells.first] = e.number;
    }
  }

  final int size;
  final List<String> grid;
  final List<String> solution;
  final List<CrosswordEntry> entries;
  final List<CrosswordEntry?> _acrossAt;
  final List<CrosswordEntry?> _downAt;
  final List<int?> _numberAt;

  int get cellCount => size * size;

  List<CrosswordEntry> get across => entries.where((e) => e.direction == Direction.across).toList(growable: false);
  List<CrosswordEntry> get down => entries.where((e) => e.direction == Direction.down).toList(growable: false);

  int rowOf(int cell) => cell ~/ size;
  int colOf(int cell) => cell % size;
  int indexOf(int row, int col) => row * size + col;

  bool isBlock(int cell) => grid[rowOf(cell)][colOf(cell)] == blockChar;

  /// The solution letter at [cell], or null for a block.
  String? solutionAt(int cell) => isBlock(cell) ? null : solution[rowOf(cell)][colOf(cell)];

  /// All non-block cell indices, row-major.
  List<int> get letterCells => [for (var i = 0; i < cellCount; i++) if (!isBlock(i)) i];

  CrosswordEntry? entryAt(int cell, Direction direction) =>
      direction == Direction.across ? _acrossAt[cell] : _downAt[cell];

  /// The clue number printed in [cell], if it starts an entry.
  int? numberAt(int cell) => _numberAt[cell];

  String answerOf(CrosswordEntry entry) => entry.cells.map((c) => solution[rowOf(c)][colOf(c)]).join();

  /// Parses and validates the payload and reveal of a crossword record.
  static CrosswordPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final size = payload['size'];
    if (size is! int) throw const FormatException('Crossword payload needs an integer "size"');
    final grid = _stringList(payload['grid'], 'grid');
    if (grid.length != size) throw FormatException('Crossword grid has ${grid.length} rows, expected $size');
    final derived = deriveEntries(grid);

    final solution = _stringList(reveal['solution'], 'solution');
    if (solution.length != size) {
      throw FormatException('Crossword solution has ${solution.length} rows, expected $size');
    }
    for (var r = 0; r < size; r++) {
      if (solution[r].length != size) {
        throw FormatException('Solution row ${r + 1} has ${solution[r].length} cells, expected $size');
      }
      for (var c = 0; c < size; c++) {
        final g = grid[r][c];
        final s = solution[r][c];
        if (g == blockChar && s != blockChar) {
          throw FormatException('Solution row ${r + 1} column ${c + 1} should be a block');
        }
        if (g == letterChar && !RegExp(r'^[A-Z]$').hasMatch(s)) {
          throw FormatException('Solution row ${r + 1} column ${c + 1} must be a letter A-Z, found "$s"');
        }
      }
    }

    final clues = payload['clues'];
    if (clues is! Map) throw const FormatException('Crossword payload needs a "clues" object');
    final entries = <CrosswordEntry>[];
    for (final direction in Direction.values) {
      final given = _clueList(clues[direction.name], direction);
      final expected = derived.where((e) => e.direction == direction).toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      if (given.length != expected.length) {
        throw FormatException(
          'Expected ${expected.length} ${direction.name} clues, found ${given.length}',
        );
      }
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final c = given[i];
        if (c.number != e.number || c.row != e.row || c.col != e.col || c.length != e.length) {
          throw FormatException(
            'Clue ${c.number} ${direction.name} (row ${c.row + 1}, column ${c.col + 1}, length ${c.length}) '
            'does not match derived entry ${e.number} ${direction.name} '
            '(row ${e.row + 1}, column ${e.col + 1}, length ${e.length})',
          );
        }
        entries.add(e.withClue(c.clue));
      }
    }
    return CrosswordPuzzle._(size: size, grid: List.unmodifiable(grid), solution: List.unmodifiable(solution), entries: List.unmodifiable(entries));
  }

  Map<String, dynamic> toPayload() => {
        'size': size,
        'grid': grid,
        'clues': {
          for (final direction in Direction.values)
            direction.name: [
              for (final e in entries)
                if (e.direction == direction) e.toJson(),
            ],
        },
      };

  Map<String, dynamic> toReveal() => {'solution': solution};

  static List<String> _stringList(Object? raw, String field) {
    if (raw is! List || raw.isEmpty || raw.any((r) => r is! String)) {
      throw FormatException('Crossword "$field" must be a non-empty list of strings');
    }
    return raw.cast<String>();
  }

  static List<_RawClue> _clueList(Object? raw, Direction direction) {
    if (raw is! List) throw FormatException('Crossword clues need a "${direction.name}" list');
    final out = <_RawClue>[];
    for (final item in raw) {
      if (item is! Map) throw FormatException('Each ${direction.name} clue must be an object');
      final number = item['number'];
      final row = item['row'];
      final col = item['col'];
      final length = item['length'];
      final clue = item['clue'];
      if (number is! int || row is! int || col is! int || length is! int) {
        throw FormatException('${direction.name} clue needs integer number, row, col and length: $item');
      }
      if (clue is! String || clue.trim().isEmpty) {
        throw FormatException('Clue $number ${direction.name} has no text');
      }
      out.add(_RawClue(number, row, col, length, clue));
    }
    out.sort((a, b) => a.number.compareTo(b.number));
    return out;
  }
}

class _RawClue {
  const _RawClue(this.number, this.row, this.col, this.length, this.clue);
  final int number;
  final int row;
  final int col;
  final int length;
  final String clue;
}

/// The answer of every entry, in entry order.
List<String> answersOf(CrosswordPuzzle puzzle) => puzzle.entries.map(puzzle.answerOf).toList(growable: false);
