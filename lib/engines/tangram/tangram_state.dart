import 'tangram_checker.dart';
import 'tangram_geometry.dart';
import 'tangram_pieces.dart';
import 'tangram_puzzle.dart';

/// One reversible step: the pieces it changed and where they were before.
/// A piece that was in the tray is recorded as null.
class TangramMove {
  const TangramMove(this.before);

  final Map<TangramPiece, TangramPlacement?> before;

  List<Map<String, dynamic>> toJson() => [
        for (final entry in before.entries)
          {'piece': entry.key.slug, if (entry.value != null) 'from': entry.value!.toJson()},
      ];

  static TangramMove fromJson(Object? raw) {
    if (raw is! List || raw.isEmpty) throw const FormatException('A tangram move must be a list of pieces');
    final before = <TangramPiece, TangramPlacement?>{};
    for (final item in raw) {
      if (item is! Map) throw const FormatException('A tangram move entry must be an object');
      final json = Map<String, dynamic>.from(item);
      final slug = json['piece'];
      if (slug is! String) throw const FormatException('A tangram move entry is missing "piece"');
      final from = json['from'];
      before[TangramPiece.fromSlug(slug)] = from == null ? null : TangramPlacement.fromJson(from);
    }
    return TangramMove(Map.unmodifiable(before));
  }
}

/// The whole play state of one tangram. Immutable: every transition returns a
/// new state. Pieces not in [placed] are still in the tray.
class TangramState {
  TangramState._({
    required this.puzzle,
    required this.placed,
    required this.selected,
    required this.undoStack,
    required this.hints,
    required this.elapsedSeconds,
  });

  factory TangramState.initial(TangramPuzzle puzzle) => TangramState._(
        puzzle: puzzle,
        placed: const {},
        selected: null,
        undoStack: const [],
        hints: 0,
        elapsedSeconds: 0,
      );

  static const int maxUndo = 60;

  final TangramPuzzle puzzle;

  /// Where each piece sits on the board. A piece with no entry is in the tray.
  final Map<TangramPiece, TangramPlacement> placed;
  final TangramPiece? selected;
  final List<TangramMove> undoStack;
  final int hints;
  final int elapsedSeconds;

  late final TangramCheck check = TangramChecker.check(puzzle.mask, placed.values);

  bool get isSolved => check.isComplete;

  bool get canUndo => undoStack.isNotEmpty;

  /// The pieces still in the tray, in their usual order.
  List<TangramPiece> get tray =>
      TangramPiece.values.where((p) => !placed.containsKey(p)).toList(growable: false);

  bool isPlaced(TangramPiece piece) => placed.containsKey(piece);

  TangramPlacement? placementOf(TangramPiece piece) => placed[piece];

  TangramState select(TangramPiece? piece) => piece == selected ? this : _copy(selected: piece);

  /// Puts [piece] on the board at ([x], [y]), keeping it inside the board.
  /// A piece already on the board keeps its turn unless one is given.
  TangramState place(TangramPiece piece, int x, int y, {int? rotation, bool? flipped}) {
    final current = placed[piece];
    final wanted = TangramPlacement(
      piece: piece,
      x: x,
      y: y,
      rotation: rotation ?? current?.rotation ?? 0,
      flipped: flipped ?? current?.flipped ?? false,
    );
    final next = _clamped(wanted);
    if (current == next) return _copy(selected: piece);
    return _apply({piece: current}, {...placed, piece: next}, selected: piece);
  }

  /// Nudges the selected piece by whole units.
  TangramState nudge(int dx, int dy) {
    final piece = selected;
    final current = piece == null ? null : placed[piece];
    if (piece == null || current == null) return this;
    return place(piece, current.x + dx, current.y + dy);
  }

  /// Turns the selected piece by [steps] eighths of a turn.
  TangramState turn(int steps) {
    final piece = selected;
    final current = piece == null ? null : placed[piece];
    if (piece == null || current == null || steps % TangramPlacement.turns == 0) return this;
    final next = _clamped(current.turned(steps));
    return _apply({piece: current}, {...placed, piece: next}, selected: piece);
  }

  /// Turns the selected piece over. Only the parallelogram has a different
  /// mirror image, so nothing else moves.
  TangramState flip() {
    final piece = selected;
    final current = piece == null ? null : placed[piece];
    if (piece == null || current == null || !piece.canFlip) return this;
    final next = _clamped(current.flip());
    return _apply({piece: current}, {...placed, piece: next}, selected: piece);
  }

  /// Sends the selected piece back to the tray.
  TangramState takeBack() {
    final piece = selected;
    final current = piece == null ? null : placed[piece];
    if (piece == null || current == null) return this;
    final next = Map<TangramPiece, TangramPlacement>.of(placed)..remove(piece);
    return _apply({piece: current}, next, selected: piece);
  }

  /// Sends every piece back to the tray.
  TangramState reset() {
    if (placed.isEmpty) return this;
    return _apply(Map<TangramPiece, TangramPlacement>.of(placed), const {}, selected: null);
  }

  /// Places one piece where the published arrangement has it, sending back
  /// anything it would sit on top of. Counts as a hint.
  TangramState hint() {
    for (final piece in TangramPiece.values) {
      final answer = puzzle.solutionFor(piece);
      if (placed[piece] == answer) continue;
      final before = <TangramPiece, TangramPlacement?>{piece: placed[piece]};
      final next = <TangramPiece, TangramPlacement>{...placed, piece: answer};
      for (final other in placed.keys) {
        if (other == piece) continue;
        if (TangramGeometry.overlapArea(placed[other]!.polygon(), answer.polygon()) > 1e-6) {
          before[other] = placed[other];
          next.remove(other);
        }
      }
      return _apply(before, next, selected: piece, hints: hints + 1);
    }
    return this;
  }

  TangramState undo() {
    if (undoStack.isEmpty) return this;
    final move = undoStack.last;
    final next = Map<TangramPiece, TangramPlacement>.of(placed);
    for (final entry in move.before.entries) {
      if (entry.value == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value!;
      }
    }
    return TangramState._(
      puzzle: puzzle,
      placed: Map.unmodifiable(next),
      selected: move.before.keys.first,
      undoStack: List.unmodifiable(undoStack.sublist(0, undoStack.length - 1)),
      hints: hints,
      elapsedSeconds: elapsedSeconds,
    );
  }

  TangramState tick(int seconds) =>
      seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  /// Shifts a placement by whole units until every corner is back inside the
  /// board, so a piece can never be dragged off the edge.
  static TangramPlacement _clamped(TangramPlacement placement) {
    const edge = TangramGeometry.boardUnits;
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final corner in placement.polygon()) {
      left = corner.x < left ? corner.x : left;
      right = corner.x > right ? corner.x : right;
      top = corner.y < top ? corner.y : top;
      bottom = corner.y > bottom ? corner.y : bottom;
    }
    var dx = 0, dy = 0;
    if (left < 0) dx = (-left).ceil();
    if (right + dx > edge) dx -= (right + dx - edge).ceil();
    if (top < 0) dy = (-top).ceil();
    if (bottom + dy > edge) dy -= (bottom + dy - edge).ceil();
    if (dx == 0 && dy == 0) return placement;
    return placement.movedTo(placement.x + dx, placement.y + dy);
  }

  TangramState _apply(
    Map<TangramPiece, TangramPlacement?> before,
    Map<TangramPiece, TangramPlacement> next, {
    TangramPiece? selected,
    int? hints,
  }) {
    final stack = [...undoStack, TangramMove(Map.unmodifiable(before))];
    return TangramState._(
      puzzle: puzzle,
      placed: Map.unmodifiable(next),
      selected: selected,
      undoStack: List.unmodifiable(stack.length > maxUndo ? stack.sublist(stack.length - maxUndo) : stack),
      hints: hints ?? this.hints,
      elapsedSeconds: elapsedSeconds,
    );
  }

  TangramState _copy({
    Object? selected = _unset,
    int? hints,
    int? elapsedSeconds,
  }) =>
      TangramState._(
        puzzle: puzzle,
        placed: placed,
        selected: identical(selected, _unset) ? this.selected : selected as TangramPiece?,
        undoStack: undoStack,
        hints: hints ?? this.hints,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
        'placed': [for (final placement in placed.values) placement.toJson()],
        if (selected != null) 'selected': selected!.slug,
        'undo': [for (final move in undoStack) move.toJson()],
        'hints': hints,
        'elapsed': elapsedSeconds,
      };

  /// Restores saved progress. Throws [FormatException] when the data is
  /// malformed or does not belong to this puzzle.
  static TangramState fromJson(TangramPuzzle puzzle, Map<String, dynamic> json) {
    final rawPlaced = json['placed'];
    if (rawPlaced is! List) throw const FormatException('Tangram progress is missing "placed"');
    final placed = <TangramPiece, TangramPlacement>{};
    for (final item in rawPlaced) {
      final placement = TangramPlacement.fromJson(item);
      if (placed.containsKey(placement.piece)) {
        throw FormatException('Tangram progress places ${placement.piece.slug} twice');
      }
      if (!placement.isOnBoard) {
        throw FormatException('Tangram progress puts ${placement.piece.slug} off the board');
      }
      placed[placement.piece] = placement;
    }
    final rawSelected = json['selected'];
    if (rawSelected != null && rawSelected is! String) {
      throw const FormatException('Tangram progress "selected" must be a piece name');
    }
    final rawUndo = json['undo'];
    if (rawUndo != null && rawUndo is! List) {
      throw const FormatException('Tangram progress "undo" must be a list');
    }
    int count(String field) {
      final raw = json[field];
      if (raw == null) return 0;
      if (raw is! int || raw < 0) throw FormatException('Tangram progress "$field" must be a whole number');
      return raw;
    }

    return TangramState._(
      puzzle: puzzle,
      placed: Map.unmodifiable(placed),
      selected: rawSelected == null ? null : TangramPiece.fromSlug(rawSelected as String),
      undoStack: List.unmodifiable((rawUndo as List? ?? const []).map(TangramMove.fromJson)),
      hints: count('hints'),
      elapsedSeconds: count('elapsed'),
    );
  }
}
