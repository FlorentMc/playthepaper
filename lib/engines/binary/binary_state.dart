import 'binary_puzzle.dart';
import 'binary_rules.dart';

/// One reversible edit of a single cell.
class BinaryMove {
  const BinaryMove({required this.cell, required this.before, required this.after});

  final int cell;
  final int before;
  final int after;

  List<int> toJson() => [cell, before, after];

  static BinaryMove fromJson(Object? raw, int cellCount) {
    if (raw is! List || raw.length != 3 || raw.any((v) => v is! int)) {
      throw const FormatException('Binary move must be a list of 3 ints');
    }
    final m = raw.cast<int>();
    if (m[0] < 0 || m[0] >= cellCount) throw FormatException('Binary move cell out of range: ${m[0]}');
    for (final v in m.skip(1)) {
      if (v != BinaryRules.empty && v != 0 && v != 1) throw FormatException('Binary move value out of range: $v');
    }
    return BinaryMove(cell: m[0], before: m[1], after: m[2]);
  }
}

/// The whole play state of one Takuzu. Immutable: every transition returns
/// a new state. Symbol 1 is shown as ● and 0 as ○.
class BinaryState {
  const BinaryState._({
    required this.puzzle,
    required this.values,
    required this.undoStack,
    required this.flagged,
    required this.hints,
    required this.elapsedSeconds,
    required this.selected,
  });

  factory BinaryState.initial(BinaryPuzzle puzzle) => BinaryState._(
        puzzle: puzzle,
        values: puzzle.givens,
        undoStack: const [],
        flagged: const {},
        hints: 0,
        elapsedSeconds: 0,
        selected: null,
      );

  final BinaryPuzzle puzzle;

  /// One value per cell: [BinaryRules.empty], 0 or 1. Givens never change.
  final List<int> values;
  final List<BinaryMove> undoStack;

  /// Cells a check marked wrong and the player has not touched since.
  final Set<int> flagged;

  /// Checks used so far.
  final int hints;
  final int elapsedSeconds;
  final int? selected;

  int get size => puzzle.size;

  bool isGiven(int index) => puzzle.isGiven(index);

  bool get canUndo => undoStack.isNotEmpty;

  bool get isFull => BinaryRules.isComplete(values);

  /// Solved by the rules themselves, not by comparison with the reveal.
  bool get isSolved => BinaryRules.isValidSolution(values, size);

  /// Cells that break a rule as the grid stands.
  Set<int> conflicts() => BinaryRules.violations(values, size);

  /// Filled cells whose value differs from the solution.
  Set<int> wrongCells() {
    final out = <int>{};
    for (var i = 0; i < values.length; i++) {
      if (values[i] != BinaryRules.empty && values[i] != puzzle.solution[i]) out.add(i);
    }
    return out;
  }

  /// How many of each symbol a line still needs: `[zeros, ones]`.
  List<int> remainingIn(List<int> line) {
    final half = size ~/ 2;
    var zeros = 0, ones = 0;
    for (final i in line) {
      if (values[i] == 0) zeros++;
      if (values[i] == 1) ones++;
    }
    return [half - zeros, half - ones];
  }

  BinaryState select(int? index) {
    if (index != null && (index < 0 || index >= values.length)) {
      throw RangeError.range(index, 0, values.length - 1, 'index');
    }
    return _copy(selected: index);
  }

  /// Sets [cell] to [value] ([BinaryRules.empty], 0 or 1). Givens are left
  /// alone, as is a cell that already holds [value].
  BinaryState setValue(int cell, int value) {
    if (cell < 0 || cell >= values.length) throw RangeError.range(cell, 0, values.length - 1, 'cell');
    if (value != BinaryRules.empty && value != 0 && value != 1) throw RangeError.range(value, -1, 1, 'value');
    if (isGiven(cell) || values[cell] == value) return _copy(selected: cell);
    final move = BinaryMove(cell: cell, before: values[cell], after: value);
    final next = List<int>.of(values, growable: false);
    next[cell] = value;
    return _copy(
      values: List<int>.unmodifiable(next),
      undoStack: [...undoStack, move],
      flagged: flagged.contains(cell) ? ({...flagged}..remove(cell)) : flagged,
      selected: cell,
    );
  }

  /// Empty → ● (1) → ○ (0) → empty.
  BinaryState cycle(int cell) {
    final v = values[cell];
    final next = v == BinaryRules.empty ? 1 : (v == 1 ? 0 : BinaryRules.empty);
    return setValue(cell, next);
  }

  BinaryState clear(int cell) => setValue(cell, BinaryRules.empty);

  BinaryState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    final next = List<int>.of(values, growable: false);
    next[move.cell] = move.before;
    return _copy(
      values: List<int>.unmodifiable(next),
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      flagged: flagged.contains(move.cell) ? ({...flagged}..remove(move.cell)) : flagged,
      selected: move.cell,
    );
  }

  /// Marks every wrong cell and counts one hint.
  BinaryState check() => _copy(flagged: wrongCells(), hints: hints + 1);

  BinaryState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'values': BinaryRules.formatCells(values),
        'undo': undoStack.map((m) => m.toJson()).toList(),
        'flagged': flagged.toList()..sort(),
        'hints': hints,
        'elapsed': elapsedSeconds,
        'selected': selected,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not belong to this puzzle.
  static BinaryState fromJson(BinaryPuzzle puzzle, Map<String, dynamic> json) {
    final rawValues = json['values'];
    if (rawValues is! String) throw const FormatException('Binary progress is missing "values"');
    final values = BinaryRules.parseCells(rawValues, puzzle.size, field: 'progress values', allowBlank: true);
    for (var i = 0; i < values.length; i++) {
      if (puzzle.isGiven(i) && values[i] != puzzle.givens[i]) {
        throw const FormatException('Binary progress does not match the puzzle givens');
      }
    }
    final rawUndo = json['undo'] ?? const [];
    if (rawUndo is! List) throw const FormatException('Binary progress "undo" must be a list');
    final undo = rawUndo.map((m) => BinaryMove.fromJson(m, puzzle.cellCount)).toList();
    final rawFlagged = json['flagged'] ?? const [];
    if (rawFlagged is! List || rawFlagged.any((v) => v is! int || v < 0 || v >= puzzle.cellCount)) {
      throw const FormatException('Binary progress "flagged" must be a list of cell indices');
    }
    int count(String field) {
      final raw = json[field];
      if (raw == null) return 0;
      if (raw is! int || raw < 0) throw FormatException('Binary progress "$field" must be a non-negative int');
      return raw;
    }

    final selected = json['selected'];
    if (selected != null && (selected is! int || selected < 0 || selected >= puzzle.cellCount)) {
      throw const FormatException('Binary progress "selected" is out of range');
    }
    return BinaryState._(
      puzzle: puzzle,
      values: List<int>.unmodifiable(values),
      undoStack: List<BinaryMove>.unmodifiable(undo),
      flagged: Set<int>.unmodifiable(rawFlagged.cast<int>()),
      hints: count('hints'),
      elapsedSeconds: count('elapsed'),
      selected: selected as int?,
    );
  }

  BinaryState _copy({
    List<int>? values,
    List<BinaryMove>? undoStack,
    Set<int>? flagged,
    int? hints,
    int? elapsedSeconds,
    Object? selected = _unset,
  }) =>
      BinaryState._(
        puzzle: puzzle,
        values: values ?? this.values,
        undoStack: undoStack == null ? this.undoStack : List<BinaryMove>.unmodifiable(undoStack),
        flagged: flagged == null ? this.flagged : Set<int>.unmodifiable(flagged),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        selected: identical(selected, _unset) ? this.selected : selected as int?,
      );

  static const Object _unset = Object();
}
