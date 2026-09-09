import 'nonogram_line.dart';
import 'nonogram_puzzle.dart';

/// What the player has marked in a cell.
enum CellMark {
  unknown('.'),
  filled('#'),
  crossed('x');

  const CellMark(this.symbol);
  final String symbol;

  static CellMark fromSymbol(String s) {
    for (final m in values) {
      if (m.symbol == s) return m;
    }
    throw FormatException('Nonogram progress has an unknown cell "$s"');
  }
}

/// What a drag stroke paints.
enum PaintMode { fill, cross }

/// One cell edit: what it held before and after.
class NonogramChange {
  const NonogramChange({required this.cell, required this.before, required this.after});

  final int cell;
  final CellMark before;
  final CellMark after;

  List<Object> toJson() => [cell, before.symbol, after.symbol];

  static NonogramChange fromJson(Object? raw, int cellCount) {
    if (raw is! List || raw.length != 3 || raw[0] is! int || raw[1] is! String || raw[2] is! String) {
      throw const FormatException('Nonogram change must be [cell, before, after]');
    }
    final cell = raw[0] as int;
    if (cell < 0 || cell >= cellCount) throw FormatException('Nonogram change cell out of range: $cell');
    return NonogramChange(cell: cell, before: CellMark.fromSymbol(raw[1] as String), after: CellMark.fromSymbol(raw[2] as String));
  }
}

/// The whole play state of one nonogram. Immutable: every transition
/// returns a new state. A stroke of several cells is one undo step.
class NonogramState {
  const NonogramState._({
    required this.puzzle,
    required this.cells,
    required this.undoStack,
    required this.redoStack,
    required this.flagged,
    required this.hints,
    required this.elapsedSeconds,
    required this.cursor,
    required this.mode,
  });

  factory NonogramState.initial(NonogramPuzzle puzzle) => NonogramState._(
        puzzle: puzzle,
        cells: List<CellMark>.unmodifiable(List<CellMark>.filled(puzzle.cellCount, CellMark.unknown)),
        undoStack: const [],
        redoStack: const [],
        flagged: const {},
        hints: 0,
        elapsedSeconds: 0,
        cursor: null,
        mode: PaintMode.fill,
      );

  final NonogramPuzzle puzzle;

  /// Row-major marks.
  final List<CellMark> cells;
  final List<List<NonogramChange>> undoStack;
  final List<List<NonogramChange>> redoStack;

  /// Cells a row check found wrong. A flag clears when its cell changes.
  final Set<int> flagged;
  final int hints;
  final int elapsedSeconds;

  /// The keyboard cursor and the cell a row check applies to.
  final int? cursor;
  final PaintMode mode;

  int get width => puzzle.width;
  int get height => puzzle.height;

  CellMark markAt(int index) => cells[index];

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  bool get isEmpty => cells.every((m) => m == CellMark.unknown);

  int get filledCount => cells.where((m) => m == CellMark.filled).length;

  /// Filled cells match the picture exactly; crossed and blank both count as empty.
  bool get isSolved {
    for (var r = 0; r < height; r++) {
      if (rowMask(r) != puzzle.rowMasks[r]) return false;
    }
    return true;
  }

  /// The filled cells of a row as a bitmask.
  int rowMask(int row) {
    var mask = 0;
    for (var c = 0; c < width; c++) {
      if (cells[row * width + c] == CellMark.filled) mask |= 1 << c;
    }
    return mask;
  }

  int columnMask(int col) {
    var mask = 0;
    for (var r = 0; r < height; r++) {
      if (cells[r * width + col] == CellMark.filled) mask |= 1 << r;
    }
    return mask;
  }

  /// True when the filled cells of the row form exactly its clue.
  bool rowSatisfied(int row) => _sameRuns(NonogramLine.runs(rowMask(row), width), puzzle.rows[row]);

  bool columnSatisfied(int col) => _sameRuns(NonogramLine.runs(columnMask(col), height), puzzle.cols[col]);

  /// Cells in [row] that contradict the picture: filled where it is empty, or
  /// crossed where it is filled. Blank cells are never wrong.
  Set<int> wrongInRow(int row) {
    final wrong = <int>{};
    for (var c = 0; c < width; c++) {
      final i = row * width + c;
      final mark = cells[i];
      if (mark == CellMark.unknown) continue;
      if ((mark == CellMark.filled) != puzzle.filledAt(row, c)) wrong.add(i);
    }
    return wrong;
  }

  /// The row the cursor is on, or null with no cursor.
  int? get cursorRow => cursor == null ? null : cursor! ~/ width;

  /// Tap: blank → filled → crossed → blank.
  NonogramState cycle(int index) {
    _checkIndex(index);
    final next = switch (cells[index]) {
      CellMark.unknown => CellMark.filled,
      CellMark.filled => CellMark.crossed,
      CellMark.crossed => CellMark.unknown,
    };
    return _edit([NonogramChange(cell: index, before: cells[index], after: next)]);
  }

  /// Sets one cell. With [extendStroke] the change joins the last undo step,
  /// so a drag across many cells undoes as one.
  NonogramState set(int index, CellMark mark, {bool extendStroke = false}) {
    _checkIndex(index);
    if (cells[index] == mark) return this;
    return _edit([NonogramChange(cell: index, before: cells[index], after: mark)], extendStroke: extendStroke);
  }

  /// Keyboard: applies [mark], or clears the cell when it already has it.
  NonogramState toggle(int index, CellMark mark) => set(index, cells[index] == mark ? CellMark.unknown : mark);

  /// What a stroke starting on [index] paints in the current mode: the
  /// mode's mark, or blank when the cell already has it.
  CellMark strokeTarget(int index) {
    final mark = mode == PaintMode.fill ? CellMark.filled : CellMark.crossed;
    return cells[index] == mark ? CellMark.unknown : mark;
  }

  NonogramState undo() {
    if (undoStack.isEmpty) return this;
    final stroke = undoStack.last;
    final next = List<CellMark>.of(cells, growable: false);
    for (final change in stroke) {
      next[change.cell] = change.before;
    }
    return _copy(
      cells: next,
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: [...redoStack, stroke],
      flagged: _without(flagged, stroke),
      cursor: stroke.last.cell,
    );
  }

  NonogramState redo() {
    if (redoStack.isEmpty) return this;
    final stroke = redoStack.last;
    final next = List<CellMark>.of(cells, growable: false);
    for (final change in stroke) {
      next[change.cell] = change.after;
    }
    return _copy(
      cells: next,
      undoStack: [...undoStack, stroke],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      flagged: _without(flagged, stroke),
      cursor: stroke.last.cell,
    );
  }

  /// Clears every mark. Time and hints are kept; the history is not.
  NonogramState reset() {
    if (isEmpty && undoStack.isEmpty && redoStack.isEmpty && flagged.isEmpty) return this;
    return _copy(
      cells: List<CellMark>.filled(puzzle.cellCount, CellMark.unknown),
      undoStack: const [],
      redoStack: const [],
      flagged: const {},
    );
  }

  /// Marks the wrong cells in [row] and counts one hint.
  NonogramState checkRow(int row) {
    if (row < 0 || row >= height) throw RangeError.range(row, 0, height - 1, 'row');
    return _copy(flagged: {...flagged, ...wrongInRow(row)}, hints: hints + 1);
  }

  NonogramState setCursor(int? index) {
    if (index != null) _checkIndex(index);
    return _copy(cursor: index);
  }

  /// Moves the cursor, clamped to the board; with no cursor, starts at the top left.
  NonogramState moveCursor(int dRow, int dCol) {
    final from = cursor;
    if (from == null) return _copy(cursor: 0);
    final row = (from ~/ width + dRow).clamp(0, height - 1);
    final col = (from % width + dCol).clamp(0, width - 1);
    return _copy(cursor: row * width + col);
  }

  NonogramState setMode(PaintMode next) => mode == next ? this : _copy(mode: next);

  NonogramState toggleMode() => _copy(mode: mode == PaintMode.fill ? PaintMode.cross : PaintMode.fill);

  NonogramState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'cells': cells.map((m) => m.symbol).join(),
        'undo': undoStack.map((s) => s.map((c) => c.toJson()).toList()).toList(),
        'redo': redoStack.map((s) => s.map((c) => c.toJson()).toList()).toList(),
        'flagged': (flagged.toList()..sort()),
        'hints': hints,
        'elapsed': elapsedSeconds,
        'cursor': cursor,
        'mode': mode.name,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not fit this puzzle.
  static NonogramState fromJson(NonogramPuzzle puzzle, Map<String, dynamic> json) {
    final count = puzzle.cellCount;
    final raw = json['cells'];
    if (raw is! String || raw.length != count) throw FormatException('Nonogram progress needs $count cells');
    final cells = List<CellMark>.unmodifiable(raw.split('').map(CellMark.fromSymbol));

    List<List<NonogramChange>> strokes(String field) {
      final list = json[field];
      if (list == null) return const [];
      if (list is! List) throw FormatException('Nonogram progress "$field" must be a list');
      return List.unmodifiable(list.map((stroke) {
        if (stroke is! List || stroke.isEmpty) throw FormatException('Nonogram progress "$field" strokes must be non-empty lists');
        return List<NonogramChange>.unmodifiable(stroke.map((c) => NonogramChange.fromJson(c, count)));
      }));
    }

    int nonNegative(String field) {
      final v = json[field];
      if (v == null) return 0;
      if (v is! int || v < 0) throw FormatException('Nonogram progress "$field" must be a non-negative int');
      return v;
    }

    final rawFlagged = json['flagged'];
    final flagged = <int>{};
    if (rawFlagged != null) {
      if (rawFlagged is! List || rawFlagged.any((f) => f is! int || f < 0 || f >= count)) {
        throw const FormatException('Nonogram progress "flagged" must list cell indices');
      }
      flagged.addAll(rawFlagged.cast<int>());
    }
    final cursor = json['cursor'];
    if (cursor != null && (cursor is! int || cursor < 0 || cursor >= count)) {
      throw const FormatException('Nonogram progress "cursor" is out of range');
    }
    final mode = json['mode'];
    return NonogramState._(
      puzzle: puzzle,
      cells: cells,
      undoStack: strokes('undo'),
      redoStack: strokes('redo'),
      flagged: Set.unmodifiable(flagged),
      hints: nonNegative('hints'),
      elapsedSeconds: nonNegative('elapsed'),
      cursor: cursor as int?,
      mode: mode == PaintMode.cross.name ? PaintMode.cross : PaintMode.fill,
    );
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= puzzle.cellCount) throw RangeError.range(index, 0, puzzle.cellCount - 1, 'index');
  }

  static bool _sameRuns(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Set<int> _without(Set<int> flagged, List<NonogramChange> stroke) {
    if (flagged.isEmpty) return flagged;
    final next = Set<int>.of(flagged);
    for (final change in stroke) {
      next.remove(change.cell);
    }
    return next;
  }

  NonogramState _edit(List<NonogramChange> changes, {bool extendStroke = false}) {
    final next = List<CellMark>.of(cells, growable: false);
    for (final change in changes) {
      next[change.cell] = change.after;
    }
    final List<List<NonogramChange>> undo;
    if (extendStroke && undoStack.isNotEmpty) {
      undo = [...undoStack.sublist(0, undoStack.length - 1), [...undoStack.last, ...changes]];
    } else {
      undo = [...undoStack, changes];
    }
    return _copy(cells: next, undoStack: undo, redoStack: const [], flagged: _without(flagged, changes));
  }

  NonogramState _copy({
    List<CellMark>? cells,
    List<List<NonogramChange>>? undoStack,
    List<List<NonogramChange>>? redoStack,
    Set<int>? flagged,
    int? hints,
    int? elapsedSeconds,
    Object? cursor = _unset,
    PaintMode? mode,
  }) =>
      NonogramState._(
        puzzle: puzzle,
        cells: cells == null ? this.cells : List<CellMark>.unmodifiable(cells),
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack.map(List<NonogramChange>.unmodifiable)),
        redoStack: redoStack == null ? this.redoStack : List.unmodifiable(redoStack.map(List<NonogramChange>.unmodifiable)),
        flagged: flagged == null ? this.flagged : Set.unmodifiable(flagged),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        cursor: identical(cursor, _unset) ? this.cursor : cursor as int?,
        mode: mode ?? this.mode,
      );

  static const Object _unset = Object();
}
