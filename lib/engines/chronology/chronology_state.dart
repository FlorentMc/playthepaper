import 'package:equatable/equatable.dart';

import 'chronology_puzzle.dart';

/// The arrangement of the four cards, the moves that led to it, the cards a
/// hint has fixed in place, and whether the order has been submitted.
/// Immutable: every transition returns a new state.
///
/// Hints fill the order from the top: each one puts the earliest event that
/// is not yet in place where it belongs and locks it there, so the locked
/// cards are always a prefix of [order] and player moves stay below it.
class ChronologyState extends Equatable {
  const ChronologyState._({
    required this.puzzle,
    required this.order,
    required this.undoStack,
    required this.lockedCount,
    required this.hints,
    required this.submitted,
  });

  ChronologyState.initial(ChronologyPuzzle puzzle)
      : this._(
          puzzle: puzzle,
          order: puzzle.eventIds,
          undoStack: const [],
          lockedCount: 0,
          hints: 0,
          submitted: false,
        );

  final ChronologyPuzzle puzzle;

  /// Event ids in the player's current order, top first.
  final List<String> order;

  /// Earlier arrangements, oldest first.
  final List<List<String>> undoStack;

  /// How many cards at the top were placed by hints and cannot move.
  final int lockedCount;
  final int hints;
  final bool submitted;

  int get length => order.length;

  bool get canUndo => !submitted && undoStack.isNotEmpty;

  bool isLocked(int index) => index < lockedCount;

  /// A card can move while play is open and neither it nor its destination is locked.
  bool canMove(int from, int to) =>
      !submitted && from != to && from >= lockedCount && to >= lockedCount && from < length && to >= 0 && to < length;

  bool get canHint => !submitted && lockedCount < ChronologyPuzzle.eventCount - 1;

  /// True when the card at [index] is where the reveal puts it.
  bool isCorrectAt(int index) => order[index] == puzzle.order[index];

  /// One point per card in its right place.
  int get points {
    var total = 0;
    for (var i = 0; i < order.length; i++) {
      if (isCorrectAt(i)) total++;
    }
    return total;
  }

  bool get isSolved => submitted && points == ChronologyPuzzle.eventCount;

  /// Takes the card at [from] out and puts it back at [to], shifting the
  /// cards between them. Returns this state when the move is not allowed.
  ChronologyState move(int from, int to) {
    if (!canMove(from, to)) return this;
    final next = List<String>.of(order);
    final id = next.removeAt(from);
    next.insert(to, id);
    return _copy(order: next, undoStack: [...undoStack, order]);
  }

  ChronologyState moveUp(int index) => move(index, index - 1);

  ChronologyState moveDown(int index) => move(index, index + 1);

  ChronologyState undo() {
    if (!canUndo) return this;
    return _copy(order: undoStack.last, undoStack: undoStack.sublist(0, undoStack.length - 1));
  }

  /// Puts the earliest event that is out of place where it belongs, locks
  /// it there and counts one hint. Cards already in place above it are
  /// locked too, so the locked cards stay a prefix. A hint cannot be undone,
  /// so it clears the undo history.
  ChronologyState hint() {
    if (!canHint) return this;
    var position = lockedCount;
    while (position < length && isCorrectAt(position)) {
      position++;
    }
    if (position >= length - 1) {
      return _copy(undoStack: const [], lockedCount: length, hints: hints + 1);
    }
    final id = puzzle.order[position];
    final next = List<String>.of(order)
      ..remove(id)
      ..insert(position, id);
    return _copy(order: next, undoStack: const [], lockedCount: position + 1, hints: hints + 1);
  }

  ChronologyState submit() => submitted ? this : _copy(submitted: true);

  /// Spoiler-free rows for the share card: the score, then one mark per position.
  List<String> shareLines() => [
        '🕰 $points/${ChronologyPuzzle.eventCount}',
        [for (var i = 0; i < order.length; i++) isCorrectAt(i) ? '🟩' : '🟥'].join(),
      ];

  Map<String, dynamic> toJson() => {
        'order': order,
        'undo': undoStack,
        'locked': lockedCount,
        'hints': hints,
        'submitted': submitted,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not belong to this puzzle.
  static ChronologyState fromJson(ChronologyPuzzle puzzle, Map<String, dynamic> json) {
    final ids = puzzle.eventIds.toSet();
    List<String> arrangement(Object? raw, String field) {
      if (raw is! List || raw.length != ids.length || raw.any((o) => o is! String)) {
        throw FormatException('Chronology progress "$field" must list the event ids');
      }
      final list = raw.cast<String>();
      if (list.toSet().length != ids.length || !ids.containsAll(list)) {
        throw FormatException('Chronology progress "$field" does not match the puzzle');
      }
      return List.unmodifiable(list);
    }

    final order = arrangement(json['order'], 'order');
    final rawUndo = json['undo'] ?? const [];
    if (rawUndo is! List) throw const FormatException('Chronology progress "undo" must be a list');
    final undo = [for (final entry in rawUndo) arrangement(entry, 'undo')];
    int count(String field, {int max = 1 << 30}) {
      final raw = json[field] ?? 0;
      if (raw is! int || raw < 0 || raw > max) throw FormatException('Chronology progress "$field" is out of range');
      return raw;
    }

    final locked = count('locked', max: ids.length);
    for (var i = 0; i < locked; i++) {
      if (order[i] != puzzle.order[i]) throw const FormatException('Chronology progress locks a card in the wrong place');
    }
    return ChronologyState._(
      puzzle: puzzle,
      order: order,
      undoStack: List.unmodifiable(undo),
      lockedCount: locked,
      hints: count('hints'),
      submitted: json['submitted'] == true,
    );
  }

  ChronologyState _copy({
    List<String>? order,
    List<List<String>>? undoStack,
    int? lockedCount,
    int? hints,
    bool? submitted,
  }) =>
      ChronologyState._(
        puzzle: puzzle,
        order: order == null ? this.order : List.unmodifiable(order),
        undoStack: undoStack == null ? this.undoStack : List.unmodifiable(undoStack.map(List<String>.unmodifiable)),
        lockedCount: lockedCount ?? this.lockedCount,
        hints: hints ?? this.hints,
        submitted: submitted ?? this.submitted,
      );

  @override
  List<Object?> get props => [puzzle, order, undoStack, lockedCount, hints, submitted];
}
