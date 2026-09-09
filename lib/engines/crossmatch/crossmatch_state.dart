import 'package:equatable/equatable.dart';

import 'crossmatch_puzzle.dart';

/// Where the nine tiles currently sit, the arrangements that led there, the
/// checks spent and whether the grid has been submitted. Immutable: every
/// transition returns a new state.
///
/// A cell holds a tile index or -1 when it is empty; a tile that is in no
/// cell is still in the tray. Because the puzzle's fits matrix has exactly
/// one perfect matching, filling every cell with a tile that satisfies both
/// its criteria is the same thing as reproducing the reveal's grid, so
/// [isSolved] can be judged by the rules alone.
class CrossmatchState extends Equatable {
  const CrossmatchState._({
    required this.puzzle,
    required this.placement,
    required this.undoStack,
    required this.wrong,
    required this.checks,
    required this.submitted,
  });

  const CrossmatchState.initial(CrossmatchPuzzle puzzle)
      : this._(
          puzzle: puzzle,
          placement: const [-1, -1, -1, -1, -1, -1, -1, -1, -1],
          undoStack: const [],
          wrong: null,
          checks: 0,
          submitted: false,
        );

  /// How many checks a player may spend. Each one is counted as a hint.
  static const int maxChecks = 3;

  final CrossmatchPuzzle puzzle;

  /// Tile index per cell, row-major, -1 where the cell is empty.
  final List<int> placement;

  /// Earlier arrangements, oldest first.
  final List<List<int>> undoStack;

  /// The cells the last check marked, or null when no check is standing.
  /// An empty list means the check found nothing wrong.
  final List<int>? wrong;

  final int checks;
  final bool submitted;

  static const int cellCount = CrossmatchPuzzle.cellCount;

  int? tileAt(int cell) => placement[cell] == -1 ? null : placement[cell];

  int? cellOf(int tile) {
    final cell = placement.indexOf(tile);
    return cell == -1 ? null : cell;
  }

  /// Tile indices that are not on the grid, in payload order.
  List<int> get tray => [for (var t = 0; t < cellCount; t++) if (!placement.contains(t)) t];

  bool get isFull => !placement.contains(-1);

  bool get canUndo => !submitted && undoStack.isNotEmpty;

  bool get canCheck => !submitted && checks < maxChecks && placement.any((t) => t != -1);

  int get checksLeft => maxChecks - checks;

  /// True when [cell] holds the tile the verified grid gives it.
  bool isCorrectAt(int cell) => placement[cell] != -1 && placement[cell] == puzzle.tileAt(cell);

  /// True when the tile in [cell] satisfies both of that cell's criteria.
  bool fitsAt(int cell) => placement[cell] != -1 && puzzle.tileFits(placement[cell], cell);

  /// True when the standing check marked [cell].
  bool isMarked(int cell) => wrong?.contains(cell) ?? false;

  /// One point per cell holding the right tile.
  int get points {
    var total = 0;
    for (var cell = 0; cell < cellCount; cell++) {
      if (isCorrectAt(cell)) total++;
    }
    return total;
  }

  /// Every cell filled with a tile that satisfies its row and its column.
  bool get rulesMet {
    for (var cell = 0; cell < cellCount; cell++) {
      if (!fitsAt(cell)) return false;
    }
    return true;
  }

  bool get isSolved => submitted && rulesMet;

  /// Puts [tile] in [cell]. Any tile already there goes back to the tray, and
  /// so does [tile] if it was somewhere else. Returns this state when the
  /// move changes nothing or play is over.
  CrossmatchState place(int tile, int cell) {
    if (submitted || tile < 0 || tile >= cellCount || cell < 0 || cell >= cellCount) return this;
    if (placement[cell] == tile) return this;
    final next = List<int>.of(placement);
    final from = next.indexOf(tile);
    if (from != -1) next[from] = -1;
    next[cell] = tile;
    return _moved(next);
  }

  /// Sends the tile in [cell] back to the tray.
  CrossmatchState clear(int cell) {
    if (submitted || cell < 0 || cell >= cellCount || placement[cell] == -1) return this;
    return _moved(List<int>.of(placement)..[cell] = -1);
  }

  CrossmatchState undo() {
    if (!canUndo) return this;
    return CrossmatchState._(
      puzzle: puzzle,
      placement: undoStack.last,
      undoStack: List.unmodifiable(undoStack.sublist(0, undoStack.length - 1)),
      wrong: null,
      checks: checks,
      submitted: submitted,
    );
  }

  /// Marks every placed tile that is not where it belongs and counts a check.
  CrossmatchState check() {
    if (!canCheck) return this;
    return CrossmatchState._(
      puzzle: puzzle,
      placement: placement,
      undoStack: undoStack,
      wrong: List.unmodifiable([
        for (var cell = 0; cell < cellCount; cell++)
          if (placement[cell] != -1 && !isCorrectAt(cell)) cell,
      ]),
      checks: checks + 1,
      submitted: submitted,
    );
  }

  CrossmatchState submit() => submitted
      ? this
      : CrossmatchState._(
          puzzle: puzzle,
          placement: placement,
          undoStack: undoStack,
          wrong: wrong,
          checks: checks,
          submitted: true,
        );

  /// The mark a cell earns on the share card: correct, wrong or left empty.
  String _mark(int cell) => isCorrectAt(cell)
      ? '🟩'
      : placement[cell] != -1
          ? '🟥'
          : '⬜';

  /// The score, then one mark per cell.
  List<String> shareLines() => [
        '🧩 $points/$cellCount',
        for (var r = 0; r < CrossmatchPuzzle.size; r++)
          [for (var c = 0; c < CrossmatchPuzzle.size; c++) _mark(CrossmatchPuzzle.cellIndex(r, c))].join(),
      ];

  Map<String, dynamic> toJson() => {
        'placement': placement,
        'undo': undoStack,
        if (wrong != null) 'wrong': wrong,
        'checks': checks,
        'submitted': submitted,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not belong to this puzzle.
  static CrossmatchState fromJson(CrossmatchPuzzle puzzle, Map<String, dynamic> json) {
    List<int> arrangement(Object? raw, String field) {
      if (raw is! List || raw.length != cellCount || raw.any((v) => v is! int || v < -1 || v >= cellCount)) {
        throw FormatException('Crossmatch progress "$field" must hold $cellCount tile indices');
      }
      final list = raw.cast<int>();
      final placed = list.where((t) => t != -1).toList();
      if (placed.toSet().length != placed.length) {
        throw FormatException('Crossmatch progress "$field" places a tile twice');
      }
      return List.unmodifiable(list);
    }

    final placement = arrangement(json['placement'], 'placement');
    final rawUndo = json['undo'] ?? const [];
    if (rawUndo is! List) throw const FormatException('Crossmatch progress "undo" must be a list');
    final undo = [for (final entry in rawUndo) arrangement(entry, 'undo')];
    final rawChecks = json['checks'] ?? 0;
    if (rawChecks is! int || rawChecks < 0 || rawChecks > maxChecks) {
      throw const FormatException('Crossmatch progress "checks" is out of range');
    }
    final rawWrong = json['wrong'];
    List<int>? wrong;
    if (rawWrong != null) {
      if (rawWrong is! List || rawWrong.any((v) => v is! int || v < 0 || v >= cellCount)) {
        throw const FormatException('Crossmatch progress "wrong" must list cells');
      }
      wrong = List.unmodifiable(rawWrong.cast<int>().toSet().toList()..sort());
    }
    return CrossmatchState._(
      puzzle: puzzle,
      placement: placement,
      undoStack: List.unmodifiable(undo),
      wrong: wrong,
      checks: rawChecks,
      submitted: json['submitted'] == true,
    );
  }

  CrossmatchState _moved(List<int> next) => CrossmatchState._(
        puzzle: puzzle,
        placement: List.unmodifiable(next),
        undoStack: List.unmodifiable([...undoStack, placement]),
        wrong: null,
        checks: checks,
        submitted: submitted,
      );

  @override
  List<Object?> get props => [puzzle, placement, undoStack, wrong, checks, submitted];
}
