import 'target_expression.dart';
import 'target_puzzle.dart';

/// A number on the table: one of the six given tiles or the result of a step.
class TargetTile {
  const TargetTile({required this.id, required this.value, this.step});

  final int id;
  final int value;

  /// The index of the step that made this tile, or null for a given tile.
  final int? step;

  bool get isGiven => step == null;
}

/// One combination of two tiles into a new one.
class TargetStep {
  const TargetStep({required this.aId, required this.a, required this.op, required this.bId, required this.b, required this.result});

  final int aId;
  final int a;
  final TargetOp op;
  final int bId;
  final int b;
  final int result;

  String get display => '$a ${op.symbol} $b = $result';

  List<Object> toJson() => [aId, op.ascii, bId];
}

/// The whole play state of one Target. Immutable: every transition returns
/// a new state. The tiles on the table follow from the steps.
class TargetState {
  TargetState._({
    required this.puzzle,
    required this.steps,
    required this.elapsedSeconds,
    required this.gaveUp,
  }) : tiles = _tableFor(puzzle, steps);

  factory TargetState.initial(TargetPuzzle puzzle) =>
      TargetState._(puzzle: puzzle, steps: const [], elapsedSeconds: 0, gaveUp: false);

  final TargetPuzzle puzzle;
  final List<TargetStep> steps;
  final int elapsedSeconds;
  final bool gaveUp;

  /// The tiles currently on the table, in display order.
  final List<TargetTile> tiles;

  int get target => puzzle.target;

  bool get canUndo => steps.isNotEmpty;

  /// Solved when a tile on the table equals the target.
  bool get isSolved => tiles.any((t) => t.value == target);

  bool get isOver => isSolved || gaveUp;

  TargetTile? tile(int id) {
    for (final t in tiles) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The step result nearest the target so far, and how far off it is.
  (int value, int off)? get closest {
    int? bestValue;
    var bestOff = 0;
    for (final s in steps) {
      final off = (target - s.result).abs();
      if (bestValue == null || off < bestOff) {
        bestValue = s.result;
        bestOff = off;
      }
    }
    return bestValue == null ? null : (bestValue, bestOff);
  }

  /// The one-line summary for the result: `Reached 431` or `Closest 429 (2 off)`.
  String get note {
    if (isSolved) return 'Reached $target';
    final c = closest;
    if (c == null) return 'Not solved';
    return 'Closest ${c.$1} (${c.$2} off)';
  }

  /// What `a op b` would make with the tiles [aId] and [bId], or null when
  /// either tile is not on the table or the result is not a positive whole
  /// number.
  int? resultOf(int aId, TargetOp op, int bId) {
    if (aId == bId) return null;
    final a = tile(aId), b = tile(bId);
    if (a == null || b == null) return null;
    return op.apply(a.value, b.value);
  }

  /// Combines two tiles into a new one. Returns this state unchanged when the
  /// step is not allowed or play is over.
  TargetState apply(int aId, TargetOp op, int bId) {
    if (isOver) return this;
    final result = resultOf(aId, op, bId);
    if (result == null) return this;
    final step = TargetStep(aId: aId, a: tile(aId)!.value, op: op, bId: bId, b: tile(bId)!.value, result: result);
    return _copy(steps: [...steps, step]);
  }

  TargetState undo() => steps.isEmpty || gaveUp ? this : _copy(steps: steps.sublist(0, steps.length - 1));

  TargetState reset() => steps.isEmpty || gaveUp ? this : _copy(steps: const []);

  TargetState giveUp() => isOver ? this : _copy(gaveUp: true);

  TargetState tick(int seconds) => seconds == 0 ? this : _copy(elapsedSeconds: elapsedSeconds + seconds);

  Map<String, dynamic> toJson() => {
        'steps': steps.map((s) => s.toJson()).toList(),
        'elapsed': elapsedSeconds,
        'gaveUp': gaveUp,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when a
  /// step is malformed or not allowed from where it stands.
  static TargetState fromJson(TargetPuzzle puzzle, Map<String, dynamic> json) {
    final rawSteps = json['steps'] ?? const [];
    if (rawSteps is! List) throw const FormatException('Target progress "steps" must be a list');
    var state = TargetState.initial(puzzle);
    for (final raw in rawSteps) {
      if (raw is! List || raw.length != 3 || raw[0] is! int || raw[1] is! String || raw[2] is! int) {
        throw const FormatException('Target step must be [aId, op, bId]');
      }
      final op = TargetOp.fromChar(raw[1] as String);
      if (op == null) throw FormatException('Target step has an unknown operation "${raw[1]}"');
      final next = state.apply(raw[0] as int, op, raw[2] as int);
      if (identical(next, state)) throw FormatException('Target step $raw is not allowed');
      state = next;
    }
    final elapsed = json['elapsed'] ?? 0;
    if (elapsed is! int || elapsed < 0) throw const FormatException('Target progress "elapsed" must be a non-negative int');
    final gaveUp = json['gaveUp'] ?? false;
    if (gaveUp is! bool) throw const FormatException('Target progress "gaveUp" must be a bool');
    return state._copy(elapsedSeconds: elapsed, gaveUp: gaveUp);
  }

  static List<TargetTile> _tableFor(TargetPuzzle puzzle, List<TargetStep> steps) {
    final table = <TargetTile>[
      for (var i = 0; i < puzzle.tiles.length; i++) TargetTile(id: i, value: puzzle.tiles[i]),
    ];
    for (var k = 0; k < steps.length; k++) {
      final s = steps[k];
      final at = table.indexWhere((t) => t.id == s.aId || t.id == s.bId);
      table.removeWhere((t) => t.id == s.aId || t.id == s.bId);
      table.insert(at, TargetTile(id: puzzle.tiles.length + k, value: s.result, step: k));
    }
    return List.unmodifiable(table);
  }

  TargetState _copy({List<TargetStep>? steps, int? elapsedSeconds, bool? gaveUp}) => TargetState._(
        puzzle: puzzle,
        steps: steps == null ? this.steps : List.unmodifiable(steps),
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        gaveUp: gaveUp ?? this.gaveUp,
      );
}
