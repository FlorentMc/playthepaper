import 'regions_grid.dart';
import 'regions_puzzle.dart';

/// One reversible edit of a single cell: its value and notes before and after.
class RegionsMove {
  const RegionsMove({
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

  static RegionsMove fromJson(Object? raw, int cellCount) {
    if (raw is! List || raw.length != 5 || raw.any((v) => v is! int)) {
      throw const FormatException('Regions move must be a list of 5 ints');
    }
    final m = raw.cast<int>();
    if (m[0] < 0 || m[0] >= cellCount) throw FormatException('Regions move cell out of range: ${m[0]}');
    return RegionsMove(cell: m[0], valueBefore: m[1], notesBefore: m[2], valueAfter: m[3], notesAfter: m[4]);
  }
}

/// The whole play state of one board. Immutable: every transition returns a
/// new state. Notes are bitmasks with bit `d` set for digit `d`. [flagged]
/// holds the cells the last check marked wrong and [revealed] the cells a
/// reveal filled; a cell leaves both when it is edited again.
class RegionsState {
  const RegionsState._({
    required this.puzzle,
    required this.values,
    required List<int> notes,
    required this.undoStack,
    required this.flagged,
    required this.revealed,
    required this.hints,
    required this.elapsedSeconds,
    required this.selected,
    required this.notesMode,
  }) : _notes = notes;

  factory RegionsState.initial(RegionsPuzzle puzzle) => RegionsState._(
        puzzle: puzzle,
        values: puzzle.givens,
        notes: List<int>.unmodifiable(List<int>.filled(puzzle.cellCount, 0)),
        undoStack: const [],
        flagged: const {},
        revealed: const {},
        hints: 0,
        elapsedSeconds: 0,
        selected: null,
        notesMode: false,
      );

  final RegionsPuzzle puzzle;

  /// One value per cell, 0 for blank. Given cells always hold their given.
  final List<int> values;
  final List<int> _notes;
  final List<RegionsMove> undoStack;
  final Set<int> flagged;
  final Set<int> revealed;
  final int hints;
  final int elapsedSeconds;
  final int? selected;
  final bool notesMode;

  RegionsGrid get grid => puzzle.grid;

  Set<int> notesAt(int index) => RegionsGrid.digitsOf(_notes[index]).toSet();

  bool hasNote(int index, int digit) => _notes[index] & RegionsGrid.bit(digit) != 0;

  bool isGiven(int index) => puzzle.isGiven(index);

  bool get canUndo => undoStack.isNotEmpty;

  bool get isFull => !values.contains(0);

  /// True when the board is full and obeys every rule: each region of N
  /// cells holds 1..N once and no equal digits touch.
  bool get isSolved => grid.isValidSolution(values);

  /// True when the selected cell exists and is not a given.
  bool get canEditSelected => selected != null && !isGiven(selected!);

  /// True when at least one cell has been filled by the player.
  bool get hasEntries {
    for (var i = 0; i < values.length; i++) {
      if (values[i] != 0 && !isGiven(i)) return true;
    }
    return false;
  }

  /// Cells breaking a rule right now, from the rules alone.
  Set<int> conflicts() => grid.violations(values);

  /// Filled cells whose value differs from the solution.
  Set<int> wrongCells() {
    final result = <int>{};
    for (var i = 0; i < values.length; i++) {
      if (values[i] != 0 && values[i] != puzzle.solution[i]) result.add(i);
    }
    return result;
  }

  RegionsState select(int? index) {
    if (index != null && (index < 0 || index >= puzzle.cellCount)) {
      throw RangeError.range(index, 0, puzzle.cellCount - 1, 'index');
    }
    return _copy(selected: index);
  }

  RegionsState toggleNotesMode() => _copy(notesMode: !notesMode);

  /// Places [digit] in the selected cell, clearing its notes. A digit above
  /// the cell's region size is ignored.
  RegionsState setValue(int digit) {
    _checkDigit(digit);
    final i = selected;
    if (i == null || isGiven(i) || values[i] == digit || digit > grid.sizeOf(i)) return this;
    return _edit(i, digit, 0);
  }

  /// Adds or removes a pencil mark in the selected empty cell.
  RegionsState toggleNote(int digit) {
    _checkDigit(digit);
    final i = selected;
    if (i == null || isGiven(i) || values[i] != 0 || digit > grid.sizeOf(i)) return this;
    return _edit(i, 0, _notes[i] ^ RegionsGrid.bit(digit));
  }

  /// [toggleNote] in notes mode, otherwise [setValue].
  RegionsState input(int digit) => notesMode ? toggleNote(digit) : setValue(digit);

  /// Clears the selected cell's value and notes.
  RegionsState erase() {
    final i = selected;
    if (i == null || isGiven(i) || (values[i] == 0 && _notes[i] == 0)) return this;
    return _edit(i, 0, 0);
  }

  RegionsState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    return _copy(
      values: _with(values, move.cell, move.valueBefore),
      notes: _with(_notes, move.cell, move.notesBefore),
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      flagged: {...flagged}..remove(move.cell),
      revealed: {...revealed}..remove(move.cell),
      selected: move.cell,
    );
  }

  /// Marks every wrong digit and counts one hint.
  RegionsState check() => _copy(flagged: wrongCells(), hints: hints + 1);

  /// Fills the selected cell with its solution digit and counts one hint.
  RegionsState reveal() {
    final i = selected;
    if (i == null || isGiven(i)) return this;
    final answer = puzzle.solution[i];
    if (values[i] == answer && _notes[i] == 0) return _copy(hints: hints + 1);
    return _edit(i, answer, 0, hints: hints + 1, revealed: {...revealed, i});
  }

  RegionsState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  /// One line of squares per board row, spoiler-free: givens dark, cells a
  /// reveal filled yellow, the player's own green, blanks white.
  List<String> shareLines() => List.generate(puzzle.height, (r) {
        final line = StringBuffer();
        for (var c = 0; c < puzzle.width; c++) {
          final i = r * puzzle.width + c;
          line.write(isGiven(i)
              ? '\u2B1B'
              : revealed.contains(i)
                  ? '\u{1F7E8}'
                  : values[i] == 0
                      ? '\u2B1C'
                      : '\u{1F7E9}');
        }
        return line.toString();
      }, growable: false);

  Map<String, dynamic> toJson() => {
        'values': RegionsGrid.formatCells(values),
        'notes': List<int>.of(_notes),
        'undo': undoStack.map((m) => m.toJson()).toList(),
        'flagged': flagged.toList()..sort(),
        'revealed': revealed.toList()..sort(),
        'hints': hints,
        'elapsed': elapsedSeconds,
        'selected': selected,
        'notesMode': notesMode,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not belong to this puzzle.
  static RegionsState fromJson(RegionsPuzzle puzzle, Map<String, dynamic> json) {
    final n = puzzle.cellCount;
    final rawValues = json['values'];
    if (rawValues is! String) throw const FormatException('Regions progress is missing "values"');
    final values = puzzle.grid.parseCells(rawValues, field: 'progress values', allowBlank: true);
    for (var i = 0; i < n; i++) {
      if (puzzle.isGiven(i) && values[i] != puzzle.givens[i]) {
        throw const FormatException('Regions progress does not match the puzzle givens');
      }
    }
    final rawNotes = json['notes'];
    if (rawNotes is! List || rawNotes.length != n || rawNotes.any((v) => v is! int)) {
      throw FormatException('Regions progress "notes" must be $n ints');
    }
    final mask = RegionsGrid.digitsUpTo(RegionsGrid.maxRegionSize);
    final notes = rawNotes.cast<int>().map((v) => v & mask).toList(growable: false);
    final rawUndo = json['undo'];
    if (rawUndo != null && rawUndo is! List) throw const FormatException('Regions progress "undo" must be a list');
    final undo = rawUndo == null ? const <RegionsMove>[] : (rawUndo as List).map((m) => RegionsMove.fromJson(m, n));
    Set<int> cells(String field) {
      final raw = json[field];
      if (raw == null) return const {};
      if (raw is! List || raw.any((v) => v is! int || v < 0 || v >= n)) {
        throw FormatException('Regions progress "$field" must be a list of cell indices');
      }
      return Set<int>.unmodifiable(raw.cast<int>());
    }

    int count(String field) {
      final raw = json[field];
      if (raw == null) return 0;
      if (raw is! int || raw < 0) throw FormatException('Regions progress "$field" must be a non-negative int');
      return raw;
    }

    final selected = json['selected'];
    if (selected != null && (selected is! int || selected < 0 || selected >= n)) {
      throw const FormatException('Regions progress "selected" is out of range');
    }
    return RegionsState._(
      puzzle: puzzle,
      values: List<int>.unmodifiable(values),
      notes: List<int>.unmodifiable(notes),
      undoStack: List<RegionsMove>.unmodifiable(undo),
      flagged: cells('flagged'),
      revealed: cells('revealed'),
      hints: count('hints'),
      elapsedSeconds: count('elapsed'),
      selected: selected as int?,
      notesMode: json['notesMode'] == true,
    );
  }

  static void _checkDigit(int digit) {
    if (digit < 1 || digit > RegionsGrid.maxRegionSize) {
      throw RangeError.range(digit, 1, RegionsGrid.maxRegionSize, 'digit');
    }
  }

  static List<int> _with(List<int> list, int index, int value) {
    final copy = List<int>.of(list, growable: false);
    copy[index] = value;
    return List<int>.unmodifiable(copy);
  }

  RegionsState _edit(int cell, int value, int noteMask, {int? hints, Set<int>? revealed}) {
    final move = RegionsMove(
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
      flagged: {...flagged}..remove(cell),
      revealed: revealed ?? ({...this.revealed}..remove(cell)),
      hints: hints,
    );
  }

  RegionsState _copy({
    List<int>? values,
    List<int>? notes,
    List<RegionsMove>? undoStack,
    Set<int>? flagged,
    Set<int>? revealed,
    int? hints,
    int? elapsedSeconds,
    Object? selected = _unset,
    bool? notesMode,
  }) =>
      RegionsState._(
        puzzle: puzzle,
        values: values ?? this.values,
        notes: notes ?? _notes,
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack),
        flagged: flagged == null ? this.flagged : Set.unmodifiable(flagged),
        revealed: revealed == null ? this.revealed : Set.unmodifiable(revealed),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        selected: identical(selected, _unset) ? this.selected : selected as int?,
        notesMode: notesMode ?? this.notesMode,
      );

  static const Object _unset = Object();
}
