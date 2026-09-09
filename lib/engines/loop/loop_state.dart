import 'loop_grid.dart';
import 'loop_puzzle.dart';
import 'loop_rules.dart';
import 'loop_solver.dart';

/// What the player has put on an edge.
enum EdgeMark {
  empty('.'),
  line('-'),
  cross('x');

  const EdgeMark(this.code);
  final String code;

  static EdgeMark fromCode(String code) =>
      values.firstWhere((m) => m.code == code, orElse: () => throw FormatException('Unknown edge mark "$code"'));
}

/// One reversible change of a single edge.
class LoopMove {
  const LoopMove({required this.edge, required this.before, required this.after});

  final int edge;
  final EdgeMark before;
  final EdgeMark after;

  List<int> toJson() => [edge, before.index, after.index];

  static LoopMove fromJson(Object? raw, LoopGrid grid) {
    if (raw is! List || raw.length != 3 || raw.any((v) => v is! int)) {
      throw const FormatException('Loop move must be a list of 3 ints');
    }
    final m = raw.cast<int>();
    if (m[0] < 0 || m[0] >= grid.edgeCount) throw FormatException('Loop move edge out of range: ${m[0]}');
    if (m[1] < 0 || m[1] >= EdgeMark.values.length || m[2] < 0 || m[2] >= EdgeMark.values.length) {
      throw const FormatException('Loop move mark out of range');
    }
    return LoopMove(edge: m[0], before: EdgeMark.values[m[1]], after: EdgeMark.values[m[2]]);
  }
}

/// The whole play state of one loop puzzle. Immutable: every transition
/// returns a new state.
class LoopState {
  const LoopState._({
    required this.puzzle,
    required this.marks,
    required this.undoStack,
    required this.redoStack,
    required this.hints,
    required this.elapsedSeconds,
    required this.cursor,
    required this.crossMode,
  });

  factory LoopState.initial(LoopPuzzle puzzle) => LoopState._(
        puzzle: puzzle,
        marks: List<EdgeMark>.unmodifiable(List<EdgeMark>.filled(puzzle.grid.edgeCount, EdgeMark.empty)),
        undoStack: const [],
        redoStack: const [],
        hints: 0,
        elapsedSeconds: 0,
        cursor: null,
        crossMode: false,
      );

  final LoopPuzzle puzzle;

  /// One mark per edge.
  final List<EdgeMark> marks;
  final List<LoopMove> undoStack;
  final List<LoopMove> redoStack;
  final int hints;
  final int elapsedSeconds;

  /// The edge under the keyboard cursor, if any.
  final int? cursor;

  /// When true a tap places a cross instead of a line.
  final bool crossMode;

  LoopGrid get grid => puzzle.grid;

  EdgeMark markAt(int edge) => marks[edge];

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  bool get hasLines => marks.contains(EdgeMark.line);

  /// The drawn lines, ignoring crosses.
  List<bool> get lines => List<bool>.generate(grid.edgeCount, (e) => marks[e] == EdgeMark.line, growable: false);

  bool get isSolved => LoopRules.isSolved(grid, puzzle.clues, lines);

  /// Why the lines do not solve the puzzle yet, or null when they do.
  String? get violation => LoopRules.violation(grid, puzzle.clues, lines);

  int cellLineCount(int cell) => LoopRules.lineCount(grid.cellEdges[cell], lines);

  int dotDegree(int dot) => LoopRules.lineCount(grid.dotEdges[dot], lines);

  /// Clue cells whose count is already met.
  Set<int> satisfiedCells() {
    final result = <int>{};
    for (var cell = 0; cell < grid.cellCount; cell++) {
      if (puzzle.hasClue(cell) && cellLineCount(cell) == puzzle.clueAt(cell)) result.add(cell);
    }
    return result;
  }

  /// Clue cells with too many lines, or too many crosses to ever reach their count.
  Set<int> brokenCells() {
    final result = <int>{};
    for (var cell = 0; cell < grid.cellCount; cell++) {
      if (!puzzle.hasClue(cell)) continue;
      var lines = 0, crosses = 0;
      for (final e in grid.cellEdges[cell]) {
        if (marks[e] == EdgeMark.line) lines++;
        if (marks[e] == EdgeMark.cross) crosses++;
      }
      final clue = puzzle.clueAt(cell);
      if (lines > clue || 4 - crosses < clue) result.add(cell);
    }
    return result;
  }

  /// Dots where three or more lines meet.
  Set<int> branchDots() {
    final result = <int>{};
    for (var dot = 0; dot < grid.dotCount; dot++) {
      if (dotDegree(dot) > 2) result.add(dot);
    }
    return result;
  }

  LoopState select(int? edge) {
    if (edge != null && (edge < 0 || edge >= grid.edgeCount)) {
      throw RangeError.range(edge, 0, grid.edgeCount - 1, 'edge');
    }
    return _copy(cursor: edge);
  }

  LoopState toggleCrossMode() => _copy(crossMode: !crossMode);

  /// A line goes down on an empty or crossed edge and comes off a lined one.
  LoopState toggleLine(int edge) => setMark(edge, marks[edge] == EdgeMark.line ? EdgeMark.empty : EdgeMark.line);

  /// A cross goes down on an empty or lined edge and comes off a crossed one.
  LoopState toggleCross(int edge) =>
      setMark(edge, marks[edge] == EdgeMark.cross ? EdgeMark.empty : EdgeMark.cross);

  /// [toggleCross] in cross mode, otherwise [toggleLine]; the cursor follows.
  LoopState tap(int edge) => (crossMode ? toggleCross(edge) : toggleLine(edge)).select(edge);

  LoopState setMark(int edge, EdgeMark mark) {
    _checkEdge(edge);
    if (marks[edge] == mark) return this;
    return _edit(edge, mark);
  }

  LoopState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    return _copy(
      marks: _with(marks, move.edge, move.before),
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: [...redoStack, move],
      cursor: move.edge,
    );
  }

  LoopState redo() {
    if (redoStack.isEmpty) return this;
    final move = redoStack.last;
    return _copy(
      marks: _with(marks, move.edge, move.after),
      undoStack: [...undoStack, move],
      redoStack: redoStack.sublist(0, redoStack.length - 1),
      cursor: move.edge,
    );
  }

  /// Corrects one wrong mark, or else fills one edge the counting rules
  /// force, or else one that trying an edge both ways settles, or else the
  /// next edge of the loop. Counts one hint. Unchanged when solved.
  LoopState hint() {
    final edge = hintEdge();
    if (edge == null) return this;
    final mark = puzzle.solution[edge] ? EdgeMark.line : EdgeMark.cross;
    return _edit(edge, mark, hints: hints + 1).select(edge);
  }

  /// The edge [hint] would set, or null when nothing is left to set.
  int? hintEdge() {
    if (isSolved) return null;
    for (var e = 0; e < grid.edgeCount; e++) {
      if ((marks[e] == EdgeMark.line && !puzzle.solution[e]) || (marks[e] == EdgeMark.cross && puzzle.solution[e])) {
        return e;
      }
    }
    final values = List<int>.generate(
      grid.edgeCount,
      (e) => switch (marks[e]) {
        EdgeMark.empty => LoopSolver.unknown,
        EdgeMark.line => 1,
        EdgeMark.cross => 0,
      },
      growable: false,
    );
    final forced = _firstNew(values, LoopSolver.propagate(grid, puzzle.clues, values)) ??
        _firstNew(values, LoopSolver.deduce(grid, puzzle.clues, values)?.values);
    if (forced != null) return forced;
    for (var dot = 0; dot < grid.dotCount; dot++) {
      if (dotDegree(dot) != 1) continue;
      for (final e in grid.dotEdges[dot]) {
        if (marks[e] == EdgeMark.empty && puzzle.solution[e]) return e;
      }
    }
    for (var e = 0; e < grid.edgeCount; e++) {
      if (marks[e] == EdgeMark.empty && puzzle.solution[e]) return e;
    }
    for (var e = 0; e < grid.edgeCount; e++) {
      if (marks[e] == EdgeMark.empty) return e;
    }
    return null;
  }

  int? _firstNew(List<int> values, List<int>? reasoned) {
    if (reasoned == null) return null;
    int? cross;
    for (var e = 0; e < grid.edgeCount; e++) {
      if (values[e] != LoopSolver.unknown || reasoned[e] == LoopSolver.unknown) continue;
      if (reasoned[e] == 1) return e;
      cross ??= e;
    }
    return cross;
  }

  LoopState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'marks': marks.map((m) => m.code).join(),
        'undo': undoStack.map((m) => m.toJson()).toList(),
        'redo': redoStack.map((m) => m.toJson()).toList(),
        'hints': hints,
        'elapsed': elapsedSeconds,
        'cursor': cursor,
        'crossMode': crossMode,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not fit this puzzle.
  static LoopState fromJson(LoopPuzzle puzzle, Map<String, dynamic> json) {
    final grid = puzzle.grid;
    final rawMarks = json['marks'];
    if (rawMarks is! String || rawMarks.length != grid.edgeCount) {
      throw FormatException('Loop progress "marks" must be ${grid.edgeCount} characters');
    }
    final marks = List<EdgeMark>.unmodifiable(rawMarks.split('').map(EdgeMark.fromCode));
    List<LoopMove> moves(String field) {
      final raw = json[field];
      if (raw == null) return const [];
      if (raw is! List) throw FormatException('Loop progress "$field" must be a list');
      return List.unmodifiable(raw.map((m) => LoopMove.fromJson(m, grid)));
    }

    int count(String field) {
      final raw = json[field];
      if (raw == null) return 0;
      if (raw is! int || raw < 0) throw FormatException('Loop progress "$field" must be a non-negative int');
      return raw;
    }

    final cursor = json['cursor'];
    if (cursor != null && (cursor is! int || cursor < 0 || cursor >= grid.edgeCount)) {
      throw const FormatException('Loop progress "cursor" is out of range');
    }
    return LoopState._(
      puzzle: puzzle,
      marks: marks,
      undoStack: moves('undo'),
      redoStack: moves('redo'),
      hints: count('hints'),
      elapsedSeconds: count('elapsed'),
      cursor: cursor as int?,
      crossMode: json['crossMode'] == true,
    );
  }

  void _checkEdge(int edge) {
    if (edge < 0 || edge >= grid.edgeCount) throw RangeError.range(edge, 0, grid.edgeCount - 1, 'edge');
  }

  static List<EdgeMark> _with(List<EdgeMark> list, int index, EdgeMark value) {
    final copy = List<EdgeMark>.of(list, growable: false);
    copy[index] = value;
    return List<EdgeMark>.unmodifiable(copy);
  }

  LoopState _edit(int edge, EdgeMark mark, {int? hints}) {
    final move = LoopMove(edge: edge, before: marks[edge], after: mark);
    return _copy(
      marks: _with(marks, edge, mark),
      undoStack: [...undoStack, move],
      redoStack: const [],
      hints: hints,
    );
  }

  LoopState _copy({
    List<EdgeMark>? marks,
    List<LoopMove>? undoStack,
    List<LoopMove>? redoStack,
    int? hints,
    int? elapsedSeconds,
    Object? cursor = _unset,
    bool? crossMode,
  }) =>
      LoopState._(
        puzzle: puzzle,
        marks: marks ?? this.marks,
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack),
        redoStack: redoStack == null ? this.redoStack : List.unmodifiable(redoStack),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        cursor: identical(cursor, _unset) ? this.cursor : cursor as int?,
        crossMode: crossMode ?? this.crossMode,
      );

  static const Object _unset = Object();
}
