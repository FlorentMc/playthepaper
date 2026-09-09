import 'kakuro_grid.dart';
import 'kakuro_puzzle.dart';

/// One reversible edit of a single cell: its value and notes before and after.
class KakuroMove {
  const KakuroMove({
    required this.cell,
    required this.valueBefore,
    required this.notesBefore,
    required this.valueAfter,
    required this.notesAfter,
  });

  final int cell;
  final int valueBefore;
  final int notesBefore;
  final int valueAfter;
  final int notesAfter;

  List<int> toJson() => [cell, valueBefore, notesBefore, valueAfter, notesAfter];

  static KakuroMove fromJson(Object? raw, KakuroGrid grid) {
    if (raw is! List || raw.length != 5 || raw.any((v) => v is! int)) {
      throw const FormatException('Kakuro move must be a list of 5 ints');
    }
    final m = raw.cast<int>();
    if (m[0] < 0 || m[0] >= grid.cellCount || !grid.isWhite(m[0])) {
      throw FormatException('Kakuro move cell is not a white cell: ${m[0]}');
    }
    return KakuroMove(cell: m[0], valueBefore: m[1], notesBefore: m[2], valueAfter: m[3], notesAfter: m[4]);
  }
}

/// How a run stands against its clue.
enum RunStatus { open, met, wrong }

/// The whole play state of one kakuro. Immutable: every transition returns a
/// new state. Notes are bitmasks with bit `d` set for digit `d`.
class KakuroState {
  const KakuroState._({
    required this.puzzle,
    required this.values,
    required List<int> notes,
    required this.undoStack,
    required this.redoStack,
    required this.wrong,
    required this.hints,
    required this.elapsedSeconds,
    required this.selected,
    required this.notesMode,
  }) : _notes = notes;

  factory KakuroState.initial(KakuroPuzzle puzzle) => KakuroState._(
        puzzle: puzzle,
        values: List<int>.unmodifiable(List<int>.filled(puzzle.grid.cellCount, 0)),
        notes: List<int>.unmodifiable(List<int>.filled(puzzle.grid.cellCount, 0)),
        undoStack: const [],
        redoStack: const [],
        wrong: const {},
        hints: 0,
        elapsedSeconds: 0,
        selected: null,
        notesMode: false,
      );

  final KakuroPuzzle puzzle;

  /// One value per cell, 0 for empty; never set on a cell that is not white.
  final List<int> values;
  final List<int> _notes;
  final List<KakuroMove> undoStack;
  final List<KakuroMove> redoStack;

  /// Cells a check marked wrong and the player has not edited since.
  final Set<int> wrong;

  /// Checks and reveals used.
  final int hints;
  final int elapsedSeconds;
  final int? selected;
  final bool notesMode;

  KakuroGrid get grid => puzzle.grid;

  Set<int> notesAt(int index) => KakuroGrid.digitsOf(_notes[index]).toSet();

  bool hasNote(int index, int digit) => _notes[index] & KakuroGrid.bit(digit) != 0;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  bool get isFull => grid.whiteCells.every((i) => values[i] != 0);

  /// Solved by the rules: every white cell filled, no digit repeated in a
  /// run, every run summing to its clue.
  bool get isSolved => grid.isSolvedBy(values);

  bool get canEditSelected => selected != null && grid.isWhite(selected!);

  /// Cells holding a digit that appears twice in one of their runs.
  Set<int> conflicts() => grid.conflicts(values);

  /// Filled cells whose value differs from the solution.
  Set<int> wrongCells() => {
        for (final i in grid.whiteCells)
          if (values[i] != 0 && values[i] != puzzle.solution[i]) i,
      };

  RunStatus runStatus(KakuroRun run) {
    var seen = 0;
    var total = 0;
    for (final c in run.cells) {
      final v = values[c];
      if (v == 0) return RunStatus.open;
      if (seen & KakuroGrid.bit(v) != 0) return RunStatus.wrong;
      seen |= KakuroGrid.bit(v);
      total += v;
    }
    return total == run.sum ? RunStatus.met : RunStatus.wrong;
  }

  KakuroState select(int? index) {
    if (index != null && (index < 0 || index >= grid.cellCount)) {
      throw RangeError.range(index, 0, grid.cellCount - 1, 'index');
    }
    return _copy(selected: index);
  }

  KakuroState toggleNotesMode() => _copy(notesMode: !notesMode);

  /// Places [digit] in the selected cell, clearing its notes.
  KakuroState setValue(int digit) {
    _checkDigit(digit);
    final i = selected;
    if (i == null || !grid.isWhite(i) || values[i] == digit) return this;
    return _edit(i, digit, 0);
  }

  /// Adds or removes a pencil mark in the selected empty cell.
  KakuroState toggleNote(int digit) {
    _checkDigit(digit);
    final i = selected;
    if (i == null || !grid.isWhite(i) || values[i] != 0) return this;
    return _edit(i, 0, _notes[i] ^ KakuroGrid.bit(digit));
  }

  /// [toggleNote] in notes mode, otherwise [setValue].
  KakuroState input(int digit) => notesMode ? toggleNote(digit) : setValue(digit);

  /// Clears the selected cell's value and notes.
  KakuroState erase() {
    final i = selected;
    if (i == null || !grid.isWhite(i) || (values[i] == 0 && _notes[i] == 0)) return this;
    return _edit(i, 0, 0);
  }

  KakuroState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    return _copy(
      values: _with(values, move.cell, move.valueBefore),
      notes: _with(_notes, move.cell, move.notesBefore),
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: [...redoStack, move],
      wrong: wrong.difference({move.cell}),
      selected: move.cell,
    );
  }

  KakuroState redo() {
    if (redoStack.isEmpty) return this;
    final move = redoStack.last;
    return _copy(
      values: _with(values, move.cell, move.valueAfter),
      notes: _with(_notes, move.cell, move.notesAfter),
      undoStack: [...undoStack, move],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      wrong: wrong.difference({move.cell}),
      selected: move.cell,
    );
  }

  /// Marks every filled cell that differs from the solution and counts one hint.
  KakuroState check() => _copy(wrong: wrongCells(), hints: hints + 1);

  /// Fills the selected cell with its solution value and counts one hint.
  KakuroState revealCell() {
    final i = selected;
    if (i == null || !grid.isWhite(i)) return this;
    final answer = puzzle.solution[i];
    if (values[i] == answer && _notes[i] == 0) return _copy(hints: hints + 1);
    return _edit(i, answer, 0, hints: hints + 1);
  }

  KakuroState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'values': List<int>.of(values),
        'notes': List<int>.of(_notes),
        'undo': undoStack.map((m) => m.toJson()).toList(),
        'redo': redoStack.map((m) => m.toJson()).toList(),
        'wrong': wrong.toList()..sort(),
        'hints': hints,
        'elapsed': elapsedSeconds,
        'selected': selected,
        'notesMode': notesMode,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not fit this puzzle.
  static KakuroState fromJson(KakuroPuzzle puzzle, Map<String, dynamic> json) {
    final grid = puzzle.grid;
    List<int> digits(String field, int max) {
      final raw = json[field];
      if (raw is! List || raw.length != grid.cellCount || raw.any((v) => v is! int || v < 0 || v > max)) {
        throw FormatException('Kakuro progress "$field" must be ${grid.cellCount} ints');
      }
      final list = raw.cast<int>();
      for (var i = 0; i < grid.cellCount; i++) {
        if (!grid.isWhite(i) && list[i] != 0) {
          throw FormatException('Kakuro progress "$field" has an entry on a cell that is not white');
        }
      }
      return List<int>.unmodifiable(list);
    }

    List<KakuroMove> moves(String field) {
      final raw = json[field];
      if (raw == null) return const [];
      if (raw is! List) throw FormatException('Kakuro progress "$field" must be a list');
      return List.unmodifiable(raw.map((m) => KakuroMove.fromJson(m, grid)));
    }

    int count(String field) {
      final raw = json[field];
      if (raw == null) return 0;
      if (raw is! int || raw < 0) throw FormatException('Kakuro progress "$field" must be a non-negative int');
      return raw;
    }

    final rawWrong = json['wrong'];
    if (rawWrong != null && (rawWrong is! List || rawWrong.any((c) => c is! int || c < 0 || c >= grid.cellCount))) {
      throw const FormatException('Kakuro progress "wrong" must be a list of cell indices');
    }
    final selected = json['selected'];
    if (selected != null && (selected is! int || selected < 0 || selected >= grid.cellCount)) {
      throw const FormatException('Kakuro progress "selected" is out of range');
    }
    return KakuroState._(
      puzzle: puzzle,
      values: digits('values', 9),
      notes: digits('notes', KakuroGrid.allDigits),
      undoStack: moves('undo'),
      redoStack: moves('redo'),
      wrong: rawWrong == null ? const {} : Set.unmodifiable((rawWrong as List).cast<int>()),
      hints: count('hints'),
      elapsedSeconds: count('elapsed'),
      selected: selected as int?,
      notesMode: json['notesMode'] == true,
    );
  }

  static void _checkDigit(int digit) {
    if (digit < 1 || digit > 9) throw RangeError.range(digit, 1, 9, 'digit');
  }

  static List<int> _with(List<int> list, int index, int value) {
    final copy = List<int>.of(list, growable: false);
    copy[index] = value;
    return List<int>.unmodifiable(copy);
  }

  KakuroState _edit(int cell, int value, int noteMask, {int? hints}) {
    final move = KakuroMove(
      cell: cell,
      valueBefore: values[cell],
      notesBefore: _notes[cell],
      valueAfter: value,
      notesAfter: noteMask,
    );
    return _copy(
      values: _with(values, cell, value),
      notes: _with(_notes, cell, noteMask),
      undoStack: [...undoStack, move],
      redoStack: const [],
      wrong: wrong.difference({cell}),
      hints: hints,
    );
  }

  KakuroState _copy({
    List<int>? values,
    List<int>? notes,
    List<KakuroMove>? undoStack,
    List<KakuroMove>? redoStack,
    Set<int>? wrong,
    int? hints,
    int? elapsedSeconds,
    Object? selected = _unset,
    bool? notesMode,
  }) =>
      KakuroState._(
        puzzle: puzzle,
        values: values ?? this.values,
        notes: notes ?? _notes,
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack),
        redoStack: redoStack == null ? this.redoStack : List.unmodifiable(redoStack),
        wrong: wrong == null ? this.wrong : Set.unmodifiable(wrong),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        selected: identical(selected, _unset) ? this.selected : selected as int?,
        notesMode: notesMode ?? this.notesMode,
      );

  static const Object _unset = Object();
}
