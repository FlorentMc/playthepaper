import 'sudoku_grid.dart';
import 'sudoku_puzzle.dart';

/// One reversible edit of a single cell: its value and notes before and after.
class SudokuMove {
  const SudokuMove({
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

  static SudokuMove fromJson(Object? raw) {
    if (raw is! List || raw.length != 5 || raw.any((v) => v is! int)) {
      throw const FormatException('Sudoku move must be a list of 5 ints');
    }
    final m = raw.cast<int>();
    if (m[0] < 0 || m[0] >= SudokuGrid.cellCount) throw FormatException('Sudoku move cell out of range: ${m[0]}');
    return SudokuMove(cell: m[0], valueBefore: m[1], notesBefore: m[2], valueAfter: m[3], notesAfter: m[4]);
  }
}

/// The whole play state of one sudoku. Immutable: every transition returns a
/// new state. Notes are stored as bitmasks with bit `d` set for digit `d`.
class SudokuState {
  const SudokuState._({
    required this.puzzle,
    required this.values,
    required List<int> notes,
    required this.undoStack,
    required this.redoStack,
    required this.mistakes,
    required this.hints,
    required this.elapsedSeconds,
    required this.selected,
    required this.notesMode,
  }) : _notes = notes;

  factory SudokuState.initial(SudokuPuzzle puzzle) => SudokuState._(
        puzzle: puzzle,
        values: puzzle.givens,
        notes: List<int>.unmodifiable(List<int>.filled(SudokuGrid.cellCount, 0)),
        undoStack: const [],
        redoStack: const [],
        mistakes: 0,
        hints: 0,
        elapsedSeconds: 0,
        selected: null,
        notesMode: false,
      );

  final SudokuPuzzle puzzle;

  /// 81 values, 0 for blank. Given cells always hold their given.
  final List<int> values;
  final List<int> _notes;
  final List<SudokuMove> undoStack;
  final List<SudokuMove> redoStack;
  final int mistakes;
  final int hints;
  final int elapsedSeconds;
  final int? selected;
  final bool notesMode;

  /// Pencil marks per cell, as digits.
  List<Set<int>> get notes => List.generate(SudokuGrid.cellCount, notesAt, growable: false);

  Set<int> notesAt(int index) => SudokuGrid.digitsOf(_notes[index]).toSet();

  bool hasNote(int index, int digit) => _notes[index] & SudokuGrid.bit(digit) != 0;

  bool isGiven(int index) => puzzle.isGiven(index);

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  bool get isFull => !values.contains(0);

  bool get isSolved {
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      if (values[i] != puzzle.solution[i]) return false;
    }
    return true;
  }

  /// True when the selected cell exists and is not a given.
  bool get canEditSelected => selected != null && !isGiven(selected!);

  /// Cells whose value is repeated in their row, column or box.
  Set<int> conflicts() {
    final result = <int>{};
    for (final unit in SudokuGrid.units) {
      for (var a = 0; a < 9; a++) {
        final va = values[unit[a]];
        if (va == 0) continue;
        for (var b = a + 1; b < 9; b++) {
          if (values[unit[b]] == va) {
            result.add(unit[a]);
            result.add(unit[b]);
          }
        }
      }
    }
    return result;
  }

  /// Filled cells whose value differs from the solution.
  Set<int> wrongCells() {
    final result = <int>{};
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      if (values[i] != 0 && values[i] != puzzle.solution[i]) result.add(i);
    }
    return result;
  }

  /// How many of each digit remain to be placed, indexed 1–9 (index 0 unused).
  List<int> remainingCounts() {
    final counts = List<int>.filled(10, 9);
    counts[0] = 0;
    for (final v in values) {
      if (v != 0) counts[v]--;
    }
    return counts;
  }

  SudokuState select(int? index) {
    if (index != null && (index < 0 || index >= SudokuGrid.cellCount)) {
      throw RangeError.range(index, 0, SudokuGrid.cellCount - 1, 'index');
    }
    return _copy(selected: index);
  }

  SudokuState toggleNotesMode() => _copy(notesMode: !notesMode);

  /// Places [digit] in the selected cell, clearing its notes.
  SudokuState setValue(int digit) {
    _checkDigit(digit);
    final i = selected;
    if (i == null || isGiven(i) || values[i] == digit) return this;
    return _edit(i, digit, 0);
  }

  /// Adds or removes a pencil mark in the selected empty cell.
  SudokuState toggleNote(int digit) {
    _checkDigit(digit);
    final i = selected;
    if (i == null || isGiven(i) || values[i] != 0) return this;
    return _edit(i, 0, _notes[i] ^ SudokuGrid.bit(digit));
  }

  /// [toggleNote] in notes mode, otherwise [setValue].
  SudokuState input(int digit) => notesMode ? toggleNote(digit) : setValue(digit);

  /// Clears the selected cell's value and notes.
  SudokuState erase() {
    final i = selected;
    if (i == null || isGiven(i) || (values[i] == 0 && _notes[i] == 0)) return this;
    return _edit(i, 0, 0);
  }

  SudokuState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    return _copy(
      values: _with(values, move.cell, move.valueBefore),
      notes: _with(_notes, move.cell, move.notesBefore),
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: [...redoStack, move],
      selected: move.cell,
    );
  }

  SudokuState redo() {
    if (redoStack.isEmpty) return this;
    final move = redoStack.last;
    return _copy(
      values: _with(values, move.cell, move.valueAfter),
      notes: _with(_notes, move.cell, move.notesAfter),
      undoStack: [...undoStack, move],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      selected: move.cell,
    );
  }

  /// Fills the selected cell with its solution value and counts one hint.
  SudokuState hint() {
    final i = selected;
    if (i == null || isGiven(i)) return this;
    final answer = puzzle.solution[i];
    if (values[i] == answer && _notes[i] == 0) return _copy(hints: hints + 1);
    return _edit(i, answer, 0, hints: hints + 1);
  }

  SudokuState recordMistake() => _copy(mistakes: mistakes + 1);

  SudokuState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'values': SudokuGrid.formatCells(values),
        'notes': List<int>.of(_notes),
        'undo': undoStack.map((m) => m.toJson()).toList(),
        'redo': redoStack.map((m) => m.toJson()).toList(),
        'mistakes': mistakes,
        'hints': hints,
        'elapsed': elapsedSeconds,
        'selected': selected,
        'notesMode': notesMode,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not belong to this puzzle.
  static SudokuState fromJson(SudokuPuzzle puzzle, Map<String, dynamic> json) {
    final rawValues = json['values'];
    if (rawValues is! String) throw const FormatException('Sudoku progress is missing "values"');
    final values = SudokuGrid.parseCells(rawValues, field: 'progress values', allowBlank: true);
    for (var i = 0; i < SudokuGrid.cellCount; i++) {
      if (puzzle.isGiven(i) && values[i] != puzzle.givens[i]) {
        throw const FormatException('Sudoku progress does not match the puzzle givens');
      }
    }
    final rawNotes = json['notes'];
    if (rawNotes is! List || rawNotes.length != SudokuGrid.cellCount || rawNotes.any((n) => n is! int)) {
      throw const FormatException('Sudoku progress "notes" must be ${SudokuGrid.cellCount} ints');
    }
    final notes = rawNotes.cast<int>().map((n) => n & SudokuGrid.allDigits).toList(growable: false);
    List<SudokuMove> moves(String field) {
      final raw = json[field];
      if (raw == null) return const [];
      if (raw is! List) throw FormatException('Sudoku progress "$field" must be a list');
      return List.unmodifiable(raw.map(SudokuMove.fromJson));
    }

    int count(String field) {
      final raw = json[field];
      if (raw == null) return 0;
      if (raw is! int || raw < 0) throw FormatException('Sudoku progress "$field" must be a non-negative int');
      return raw;
    }

    final selected = json['selected'];
    if (selected != null && (selected is! int || selected < 0 || selected >= SudokuGrid.cellCount)) {
      throw const FormatException('Sudoku progress "selected" is out of range');
    }
    return SudokuState._(
      puzzle: puzzle,
      values: List<int>.unmodifiable(values),
      notes: List<int>.unmodifiable(notes),
      undoStack: moves('undo'),
      redoStack: moves('redo'),
      mistakes: count('mistakes'),
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

  SudokuState _edit(int cell, int value, int noteMask, {int? hints}) {
    final move = SudokuMove(
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
      hints: hints,
    );
  }

  SudokuState _copy({
    List<int>? values,
    List<int>? notes,
    List<SudokuMove>? undoStack,
    List<SudokuMove>? redoStack,
    int? mistakes,
    int? hints,
    int? elapsedSeconds,
    Object? selected = _unset,
    bool? notesMode,
  }) =>
      SudokuState._(
        puzzle: puzzle,
        values: values ?? this.values,
        notes: notes ?? _notes,
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack),
        redoStack: redoStack == null ? this.redoStack : List.unmodifiable(redoStack),
        mistakes: mistakes ?? this.mistakes,
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        selected: identical(selected, _unset) ? this.selected : selected as int?,
        notesMode: notesMode ?? this.notesMode,
      );

  static const Object _unset = Object();
}
