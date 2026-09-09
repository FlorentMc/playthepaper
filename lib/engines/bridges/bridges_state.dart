import 'bridges_layout.dart';
import 'bridges_puzzle.dart';
import 'bridges_solver.dart';

/// One reversible change to the bridges on a pair.
class BridgesMove {
  const BridgesMove({required this.pair, required this.before, required this.after});

  final int pair;
  final int before;
  final int after;

  List<int> toJson() => [pair, before, after];

  static BridgesMove fromJson(Object? raw, int pairCount) {
    if (raw is! List || raw.length != 3 || raw.any((v) => v is! int)) {
      throw const FormatException('Bridges move must be a list of 3 ints');
    }
    final m = raw.cast<int>();
    if (m[0] < 0 || m[0] >= pairCount) throw FormatException('Bridges move pair out of range: ${m[0]}');
    return BridgesMove(pair: m[0], before: m[1], after: m[2]);
  }
}

/// How an island stands against its number.
enum BridgesIslandStatus { under, complete, over }

/// The whole play state of one Bridges puzzle. Immutable: every transition
/// returns a new state. [board] holds the bridges on each pair.
class BridgesState {
  const BridgesState._({
    required this.puzzle,
    required this.board,
    required this.undoStack,
    required this.hints,
    required this.elapsedSeconds,
    required this.selected,
  });

  factory BridgesState.initial(BridgesPuzzle puzzle) => BridgesState._(
        puzzle: puzzle,
        board: List<int>.unmodifiable(List<int>.filled(puzzle.layout.pairs.length, 0)),
        undoStack: const [],
        hints: 0,
        elapsedSeconds: 0,
        selected: null,
      );

  final BridgesPuzzle puzzle;
  final List<int> board;
  final List<BridgesMove> undoStack;
  final int hints;
  final int elapsedSeconds;

  /// The island a bridge will be drawn from, after a first tap.
  final int? selected;

  BridgesLayout get layout => puzzle.layout;

  bool get canUndo => undoStack.isNotEmpty;

  bool get isSolved => layout.isSolution(board);

  /// The first rule the board breaks, or null when it is solved.
  BridgesFault? get fault => layout.firstFault(board);

  int load(int island) => layout.load(board, island);

  BridgesIslandStatus status(int island) {
    final need = layout.islands[island].count;
    final have = load(island);
    if (have < need) return BridgesIslandStatus.under;
    return have == need ? BridgesIslandStatus.complete : BridgesIslandStatus.over;
  }

  int get completeIslands {
    var n = 0;
    for (var i = 0; i < layout.islands.length; i++) {
      if (status(i) == BridgesIslandStatus.complete) n++;
    }
    return n;
  }

  /// True when a bridge on [pair] would cross one already drawn.
  bool wouldCross(int pair) => layout.pairs[pair].crossings.any((q) => board[q] > 0);

  /// Islands the selected island can be bridged to.
  Set<int> get reachable {
    final s = selected;
    if (s == null) return const {};
    return {for (final p in layout.pairsOf[s]) layout.pairs[p].other(s)};
  }

  BridgesState select(int? island) {
    if (island != null && (island < 0 || island >= layout.islands.length)) {
      throw RangeError.range(island, 0, layout.islands.length - 1, 'island');
    }
    return _copy(selected: island);
  }

  /// A tap on an island: the first tap selects, a tap on the selected
  /// island clears, a tap on an island in line cycles the bridges between
  /// them (one, two, none) and keeps the selection, and any other island
  /// becomes the new selection.
  BridgesState tap(int island) {
    final s = selected;
    if (s == null || s == island) return select(s == null ? island : null);
    final pair = layout.pairBetween(s, island);
    if (pair == null) return select(island);
    return cycle(pair);
  }

  BridgesState cycle(int pair) => setBridges(pair, (board[pair] + 1) % (BridgesLayout.maxBridges + 1));

  /// Sets the bridges on [pair]. Refused, returning this state, when the
  /// bridge would cross one already drawn.
  BridgesState setBridges(int pair, int count) {
    if (count < 0 || count > BridgesLayout.maxBridges) {
      throw RangeError.range(count, 0, BridgesLayout.maxBridges, 'count');
    }
    if (count == board[pair] || (count > 0 && wouldCross(pair))) return this;
    return _edit(pair, count);
  }

  BridgesState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    return _copy(
      board: _with(board, move.pair, move.before),
      undoStack: undoStack.sublist(0, undoStack.length - 1),
    );
  }

  /// Draws one bridge that must be there and counts a hint. A bridge the
  /// solution does not have is removed first; otherwise propagation from
  /// the bridges drawn so far picks a certain one, falling back to the
  /// solution when only a guess would find it. No change once solved.
  BridgesState hint() {
    if (isSolved) return this;
    for (var p = 0; p < board.length; p++) {
      if (board[p] > puzzle.solution[p]) return _edit(p, puzzle.solution[p], hints: hints + 1);
    }
    final bounds = BridgesSolver.propagate(layout, lower: board);
    if (bounds != null) {
      for (var p = 0; p < board.length; p++) {
        if (bounds.min[p] > board[p]) return _edit(p, board[p] + 1, hints: hints + 1);
      }
    }
    for (var p = 0; p < board.length; p++) {
      if (puzzle.solution[p] > board[p]) return _edit(p, board[p] + 1, hints: hints + 1);
    }
    return this;
  }

  BridgesState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'bridges': List<int>.of(board),
        'undo': undoStack.map((m) => m.toJson()).toList(),
        'hints': hints,
        'elapsed': elapsedSeconds,
        'selected': selected,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or breaks a rule no move could have broken.
  static BridgesState fromJson(BridgesPuzzle puzzle, Map<String, dynamic> json) {
    final pairCount = puzzle.layout.pairs.length;
    final raw = json['bridges'];
    if (raw is! List || raw.length != pairCount || raw.any((b) => b is! int)) {
      throw FormatException('Bridges progress "bridges" must be $pairCount ints');
    }
    final board = raw.cast<int>();
    if (board.any((b) => b < 0 || b > BridgesLayout.maxBridges)) {
      throw const FormatException('Bridges progress has an impossible bridge count');
    }
    if (puzzle.layout.crossingPairs(board).isNotEmpty) {
      throw const FormatException('Bridges progress has crossing bridges');
    }
    final rawUndo = json['undo'];
    if (rawUndo != null && rawUndo is! List) throw const FormatException('Bridges progress "undo" must be a list');
    final undo = rawUndo == null ? const <BridgesMove>[] : rawUndo.map((m) => BridgesMove.fromJson(m, pairCount));

    int count(String field) {
      final v = json[field];
      if (v == null) return 0;
      if (v is! int || v < 0) throw FormatException('Bridges progress "$field" must be a non-negative int');
      return v;
    }

    final selected = json['selected'];
    if (selected != null && (selected is! int || selected < 0 || selected >= puzzle.layout.islands.length)) {
      throw const FormatException('Bridges progress "selected" is out of range');
    }
    return BridgesState._(
      puzzle: puzzle,
      board: List<int>.unmodifiable(board),
      undoStack: List.unmodifiable(undo),
      hints: count('hints'),
      elapsedSeconds: count('elapsed'),
      selected: selected as int?,
    );
  }

  static List<int> _with(List<int> list, int index, int value) {
    final copy = List<int>.of(list, growable: false);
    copy[index] = value;
    return List<int>.unmodifiable(copy);
  }

  BridgesState _edit(int pair, int count, {int? hints}) => _copy(
        board: _with(board, pair, count),
        undoStack: [...undoStack, BridgesMove(pair: pair, before: board[pair], after: count)],
        hints: hints,
      );

  BridgesState _copy({
    List<int>? board,
    List<BridgesMove>? undoStack,
    int? hints,
    int? elapsedSeconds,
    Object? selected = _unset,
  }) =>
      BridgesState._(
        puzzle: puzzle,
        board: board ?? this.board,
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack),
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        selected: identical(selected, _unset) ? this.selected : selected as int?,
      );

  static const Object _unset = Object();
}
