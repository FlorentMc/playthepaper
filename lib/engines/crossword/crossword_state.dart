import 'crossword_puzzle.dart';

/// A keyboard arrow, for moving the selection around the grid.
enum Arrow { up, down, left, right }

/// The player's progress on one crossword. Immutable; every action returns
/// a new state. Revealed cells are locked and cannot be edited.
class CrosswordState {
  const CrosswordState._({
    required this.puzzle,
    required this.letters,
    required this.wrong,
    required this.revealed,
    required this.hints,
    required this.elapsedSeconds,
    required this.selected,
    required this.direction,
  });

  factory CrosswordState.initial(CrosswordPuzzle puzzle) => CrosswordState._(
        puzzle: puzzle,
        letters: List.unmodifiable(List<String?>.filled(puzzle.cellCount, null)),
        wrong: const {},
        revealed: const {},
        hints: 0,
        elapsedSeconds: 0,
        selected: puzzle.entries.first.cells.first,
        direction: puzzle.entries.first.direction,
      );

  /// The finished grid, for showing a completed puzzle read-only.
  factory CrosswordState.solved(CrosswordPuzzle puzzle) => CrosswordState.initial(puzzle)._copy(
        letters: [for (var i = 0; i < puzzle.cellCount; i++) puzzle.solutionAt(i)],
      );

  final CrosswordPuzzle puzzle;

  /// One entry per cell; null when empty or a block.
  final List<String?> letters;

  /// Cells marked wrong by a check and not yet retyped.
  final Set<int> wrong;

  /// Cells filled by a reveal; these are locked.
  final Set<int> revealed;

  /// Checks and reveals used.
  final int hints;
  final int elapsedSeconds;
  final int selected;
  final Direction direction;

  CrosswordEntry get currentEntry => puzzle.entryAt(selected, direction)!;

  String? letterAt(int cell) => letters[cell];
  bool isWrong(int cell) => wrong.contains(cell);
  bool isRevealed(int cell) => revealed.contains(cell);
  bool isLocked(int cell) => revealed.contains(cell);

  bool get isSolved => puzzle.letterCells.every((c) => letters[c] == puzzle.solutionAt(c));

  bool get isFull => puzzle.letterCells.every((c) => letters[c] != null);

  /// True when every cell of [entry] has a letter.
  bool isEntryFull(CrosswordEntry entry) => entry.cells.every((c) => letters[c] != null);

  /// Cells in [cells] that hold a letter differing from the solution.
  Iterable<int> wrongIn(Iterable<int> cells) =>
      cells.where((c) => letters[c] != null && letters[c] != puzzle.solutionAt(c));

  // ------------------------------------------------------------------ typing

  /// Writes [letter] into the selected cell and advances within the entry.
  /// At the end of the entry the selection moves on to the next entry that
  /// still has an empty cell. A locked cell is skipped, not overwritten.
  CrosswordState type(String letter) {
    final ch = letter.toUpperCase();
    if (!RegExp(r'^[A-Z]$').hasMatch(ch)) return this;
    if (isLocked(selected)) return _advance();
    final next = List<String?>.of(letters);
    next[selected] = ch;
    return _copy(letters: next, wrong: wrong.difference({selected}))._advance();
  }

  /// Clears the selected cell, or moves back one cell in the entry and clears
  /// that one when the selected cell is already empty or locked.
  CrosswordState backspace() {
    if (letters[selected] != null && !isLocked(selected)) return _clear(selected);
    final cells = currentEntry.cells;
    final i = cells.indexOf(selected);
    if (i <= 0) return this;
    final prev = cells[i - 1];
    final moved = _copy(selected: prev);
    return moved.isLocked(prev) ? moved : moved._clear(prev);
  }

  CrosswordState _clear(int cell) {
    final next = List<String?>.of(letters);
    next[cell] = null;
    return _copy(letters: next, wrong: wrong.difference({cell}));
  }

  CrosswordState _advance() {
    final cells = currentEntry.cells;
    final i = cells.indexOf(selected);
    if (i < cells.length - 1) return _copy(selected: cells[i + 1]);
    final ordered = puzzle.entries;
    final start = ordered.indexOf(currentEntry);
    for (var k = 1; k <= ordered.length; k++) {
      final e = ordered[(start + k) % ordered.length];
      final empty = e.cells.where((c) => letters[c] == null);
      if (empty.isNotEmpty) return _copy(selected: empty.first, direction: e.direction);
    }
    return this;
  }

  // --------------------------------------------------------------- selection

  CrosswordState select(int cell) {
    if (cell < 0 || cell >= puzzle.cellCount || puzzle.isBlock(cell)) return this;
    final dir = puzzle.entryAt(cell, direction) != null ? direction : direction.other;
    return _copy(selected: cell, direction: dir);
  }

  CrosswordState toggleDirection() {
    final other = direction.other;
    if (puzzle.entryAt(selected, other) == null) return this;
    return _copy(direction: other);
  }

  /// Moves to the nearest letter cell in the arrow's direction, skipping
  /// blocks, and reads along that axis when the new cell allows it.
  CrosswordState move(Arrow arrow) {
    final (dr, dc) = switch (arrow) {
      Arrow.up => (-1, 0),
      Arrow.down => (1, 0),
      Arrow.left => (0, -1),
      Arrow.right => (0, 1),
    };
    var r = puzzle.rowOf(selected);
    var c = puzzle.colOf(selected);
    while (true) {
      r += dr;
      c += dc;
      if (r < 0 || r >= puzzle.size || c < 0 || c >= puzzle.size) return this;
      if (!puzzle.isBlock(puzzle.indexOf(r, c))) break;
    }
    final cell = puzzle.indexOf(r, c);
    final axis = dr == 0 ? Direction.across : Direction.down;
    final Direction dir;
    if (puzzle.entryAt(cell, axis) != null) {
      dir = axis;
    } else if (puzzle.entryAt(cell, direction) != null) {
      dir = direction;
    } else {
      dir = direction.other;
    }
    return _copy(selected: cell, direction: dir);
  }

  CrosswordState nextClue() => _jumpClue(1);
  CrosswordState prevClue() => _jumpClue(-1);

  CrosswordState _jumpClue(int step) {
    final ordered = puzzle.entries;
    final i = ordered.indexOf(currentEntry);
    return selectEntry(ordered[(i + step + ordered.length) % ordered.length]);
  }

  /// Selects [entry] at its first empty cell, or its first cell when full.
  CrosswordState selectEntry(CrosswordEntry entry) {
    final empty = entry.cells.where((c) => letters[c] == null);
    return _copy(selected: empty.isEmpty ? entry.cells.first : empty.first, direction: entry.direction);
  }

  // ------------------------------------------------------- check and reveal

  CrosswordState checkCell() => _check([selected]);
  CrosswordState checkWord() => _check(currentEntry.cells);
  CrosswordState checkPuzzle() => _check(puzzle.letterCells);

  CrosswordState _check(Iterable<int> cells) => _copy(wrong: {...wrong, ...wrongIn(cells)}, hints: hints + 1);

  CrosswordState revealCell() => _reveal([selected]);
  CrosswordState revealWord() => _reveal(currentEntry.cells);
  CrosswordState revealPuzzle() => _reveal(puzzle.letterCells);

  CrosswordState _reveal(Iterable<int> cells) {
    final next = List<String?>.of(letters);
    for (final c in cells) {
      next[c] = puzzle.solutionAt(c);
    }
    return _copy(
      letters: next,
      wrong: wrong.difference(cells.toSet()),
      revealed: {...revealed, ...cells},
      hints: hints + 1,
    );
  }

  // ------------------------------------------------------------------- time

  CrosswordState tick() => _copy(elapsedSeconds: elapsedSeconds + 1);

  // ------------------------------------------------------------ persistence

  Map<String, dynamic> toJson() => {
        'letters': [
          for (var i = 0; i < puzzle.cellCount; i++)
            puzzle.isBlock(i) ? blockChar : (letters[i] ?? letterChar),
        ].join(),
        'wrong': (wrong.toList()..sort()),
        'revealed': (revealed.toList()..sort()),
        'hints': hints,
        'elapsedSeconds': elapsedSeconds,
        'selected': selected,
        'direction': direction.name,
      };

  /// Restores saved progress. Throws [FormatException] when the data does
  /// not fit [puzzle], so a caller can fall back to a fresh state.
  static CrosswordState fromJson(CrosswordPuzzle puzzle, Map<String, dynamic> json) {
    final raw = json['letters'];
    if (raw is! String || raw.length != puzzle.cellCount) {
      throw FormatException('Crossword progress has ${raw is String ? raw.length : 'no'} letters, expected ${puzzle.cellCount}');
    }
    final letters = <String?>[];
    for (var i = 0; i < puzzle.cellCount; i++) {
      final ch = raw[i];
      if (puzzle.isBlock(i)) {
        letters.add(null);
      } else if (ch == letterChar || ch == blockChar) {
        letters.add(null);
      } else if (RegExp(r'^[A-Z]$').hasMatch(ch)) {
        letters.add(ch);
      } else {
        throw FormatException('Crossword progress has an invalid letter "$ch"');
      }
    }
    final state = CrosswordState.initial(puzzle)._copy(
      letters: letters,
      wrong: _cellSet(json['wrong'], puzzle, 'wrong'),
      revealed: _cellSet(json['revealed'], puzzle, 'revealed'),
      hints: _count(json['hints'], 'hints'),
      elapsedSeconds: _count(json['elapsedSeconds'], 'elapsedSeconds'),
    );
    final selected = json['selected'];
    final direction = Direction.values.where((d) => d.name == json['direction']).firstOrNull;
    if (selected is int && selected >= 0 && selected < puzzle.cellCount && !puzzle.isBlock(selected)) {
      final restored = state.select(selected);
      return direction != null && direction != restored.direction ? restored.toggleDirection() : restored;
    }
    return state;
  }

  static Set<int> _cellSet(Object? raw, CrosswordPuzzle puzzle, String field) {
    if (raw == null) return const {};
    if (raw is! List) throw FormatException('Crossword progress "$field" must be a list');
    final out = <int>{};
    for (final v in raw) {
      if (v is! int || v < 0 || v >= puzzle.cellCount || puzzle.isBlock(v)) {
        throw FormatException('Crossword progress "$field" has an invalid cell $v');
      }
      out.add(v);
    }
    return out;
  }

  static int _count(Object? raw, String field) {
    if (raw == null) return 0;
    if (raw is! int || raw < 0) throw FormatException('Crossword progress "$field" must be a non-negative integer');
    return raw;
  }

  CrosswordState _copy({
    List<String?>? letters,
    Set<int>? wrong,
    Set<int>? revealed,
    int? hints,
    int? elapsedSeconds,
    int? selected,
    Direction? direction,
  }) =>
      CrosswordState._(
        puzzle: puzzle,
        letters: letters == null ? this.letters : List.unmodifiable(letters),
        wrong: wrong == null ? this.wrong : Set.unmodifiable(wrong),
        revealed: revealed == null ? this.revealed : Set.unmodifiable(revealed),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        selected: selected ?? this.selected,
        direction: direction ?? this.direction,
      );
}
