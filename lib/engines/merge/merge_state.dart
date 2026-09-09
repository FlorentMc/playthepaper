import 'merge_puzzle.dart';
import 'merge_rules.dart';

/// The board as it stood before the last push, kept so one move can be taken
/// back. The generator state goes back with it, so the tile that spawned
/// after the undone move is drawn again next time.
class MergeSnapshot {
  const MergeSnapshot({
    required this.tiles,
    required this.score,
    required this.moves,
    required this.randomState,
  });

  final List<int> tiles;
  final int score;
  final int moves;
  final int randomState;

  Map<String, dynamic> toJson() => {
        'tiles': List<int>.of(tiles),
        'score': score,
        'moves': moves,
        'random': randomState,
      };

  static MergeSnapshot fromJson(Object? raw, int size) {
    if (raw is! Map) throw const FormatException('Merge progress "previous" must be a map');
    final json = Map<String, dynamic>.from(raw);
    return MergeSnapshot(
      tiles: MergeState._tiles(json['tiles'], size, 'previous tiles'),
      score: MergeState._count(json, 'score', 'previous'),
      moves: MergeState._count(json, 'moves', 'previous'),
      randomState: MergeState._randomState(json, 'previous'),
    );
  }
}

/// One game of Merge, daily or unlimited. Immutable: every transition returns
/// a new state, and the whole state — board, score, generator and the one
/// step of history — round trips through JSON.
class MergeState {
  const MergeState._({
    required this.seed,
    required this.size,
    required this.tiles,
    required this.score,
    required this.moves,
    required this.randomState,
    required this.undosUsed,
    required this.keepGoing,
    required this.finished,
    required this.spawned,
    required this.merged,
    required this.previous,
  });

  /// A fresh game from [seed]: two tiles on an empty board.
  factory MergeState.start({required int seed, int size = 4}) {
    MergeRules.checkSize(size);
    final random = MergeRandom(seed);
    final tiles = MergeRules.opening(random, size);
    return MergeState._(
      seed: MergeRandom.normalise(seed),
      size: size,
      tiles: List<int>.unmodifiable(tiles),
      score: 0,
      moves: 0,
      randomState: random.state,
      undosUsed: 0,
      keepGoing: false,
      finished: false,
      spawned: null,
      merged: const {},
      previous: null,
    );
  }

  factory MergeState.of(MergePuzzle puzzle) => MergeState.start(seed: puzzle.seed, size: puzzle.size);

  /// The seed the game was dealt from; the daily checks it against its puzzle.
  final int seed;
  final int size;

  /// `size × size` tile values, row-major, 0 for an empty cell.
  final List<int> tiles;
  final int score;
  final int moves;

  /// The spawn generator, ready for the next tile.
  final int randomState;

  /// Moves taken back. The daily counts each one as a hint.
  final int undosUsed;

  /// True once the player has chosen to play on past 2048.
  final bool keepGoing;

  /// True once the player has stopped the game themselves.
  final bool finished;

  /// Where the last tile appeared, for the board to mark it.
  final int? spawned;

  /// Cells formed by a merge on the last push.
  final Set<int> merged;

  final MergeSnapshot? previous;

  int get bestTile => MergeRules.bestTile(tiles);

  int get emptyCount => MergeRules.emptyCells(tiles).length;

  /// True once a 2048 tile has been made. Tiles never shrink, so this stays
  /// true for the rest of the game.
  bool get isSolved => bestTile >= MergeRules.winningTile;

  /// True when no push would change the board.
  bool get isStuck => !MergeRules.hasMove(tiles, size);

  bool get isOver => finished || isStuck;

  bool get canUndo => previous != null && !isOver;

  /// True when 2048 has just been reached and the player has not yet said
  /// whether to play on.
  bool get awaitsChoice => isSolved && !keepGoing && !finished;

  /// Pushes the board. A push that changes nothing is not a move: it scores
  /// nothing, spawns nothing and returns this same state.
  MergeState move(MergeDirection direction) {
    if (isOver) return this;
    final slide = MergeRules.slide(tiles, size, direction);
    if (!slide.changed) return this;
    final random = MergeRandom(randomState);
    final next = List<int>.of(slide.tiles, growable: false);
    final at = MergeRules.spawn(next, random);
    return _copy(
      tiles: List<int>.unmodifiable(next),
      score: score + slide.gained,
      moves: moves + 1,
      randomState: random.state,
      spawned: at < 0 ? null : at,
      merged: Set<int>.unmodifiable(slide.merged),
      previous: MergeSnapshot(tiles: tiles, score: score, moves: moves, randomState: randomState),
    );
  }

  /// Takes back the last push, generator and all. Only one step is kept.
  MergeState undo() {
    final p = previous;
    if (p == null || isOver) return this;
    return _copy(
      tiles: List<int>.unmodifiable(p.tiles),
      score: p.score,
      moves: p.moves,
      randomState: p.randomState,
      undosUsed: undosUsed + 1,
      spawned: null,
      merged: const {},
      previous: null,
    );
  }

  /// Stops the game where it stands.
  MergeState finish() => finished ? this : _copy(finished: true);

  /// Plays on past 2048.
  MergeState keepPlaying() => keepGoing ? this : _copy(keepGoing: true);

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'size': size,
        'tiles': List<int>.of(tiles),
        'score': score,
        'moves': moves,
        'random': randomState,
        'undos': undosUsed,
        'keepGoing': keepGoing,
        'finished': finished,
        if (spawned != null) 'spawned': spawned,
        if (merged.isNotEmpty) 'merged': (merged.toList()..sort()),
        if (previous != null) 'previous': previous!.toJson(),
      };

  /// Restores a saved game. Throws [FormatException] when the data is
  /// malformed; the screen falls back to a new game.
  static MergeState fromJson(Map<String, dynamic> json) {
    final rawSize = json['size'];
    if (rawSize is! int) throw const FormatException('Merge progress is missing "size"');
    MergeRules.checkSize(rawSize);
    final rawSeed = json['seed'];
    if (rawSeed is! int || rawSeed < 1 || rawSeed > 0xFFFFFFFF) {
      throw const FormatException('Merge progress "seed" is out of range');
    }
    final tiles = _tiles(json['tiles'], rawSize, 'tiles');
    final cells = rawSize * rawSize;
    final spawned = json['spawned'];
    if (spawned != null && (spawned is! int || spawned < 0 || spawned >= cells)) {
      throw const FormatException('Merge progress "spawned" is out of range');
    }
    final rawMerged = json['merged'];
    final merged = <int>{};
    if (rawMerged != null) {
      if (rawMerged is! List) throw const FormatException('Merge progress "merged" must be a list');
      for (final v in rawMerged) {
        if (v is! int || v < 0 || v >= cells) {
          throw const FormatException('Merge progress "merged" is out of range');
        }
        merged.add(v);
      }
    }
    return MergeState._(
      seed: rawSeed,
      size: rawSize,
      tiles: List<int>.unmodifiable(tiles),
      score: _count(json, 'score', 'progress'),
      moves: _count(json, 'moves', 'progress'),
      randomState: _randomState(json, 'progress'),
      undosUsed: _count(json, 'undos', 'progress'),
      keepGoing: json['keepGoing'] == true,
      finished: json['finished'] == true,
      spawned: spawned as int?,
      merged: Set<int>.unmodifiable(merged),
      previous: json['previous'] == null ? null : MergeSnapshot.fromJson(json['previous'], rawSize),
    );
  }

  static List<int> _tiles(Object? raw, int size, String field) {
    final cells = size * size;
    if (raw is! List || raw.length != cells) {
      throw FormatException('Merge progress "$field" must be $cells values');
    }
    final out = List<int>.filled(cells, 0, growable: false);
    for (var i = 0; i < cells; i++) {
      final v = raw[i];
      if (v is! int || (v != 0 && !MergeRules.isTile(v))) {
        throw FormatException('Merge progress "$field" holds an impossible value: ${raw[i]}');
      }
      out[i] = v;
    }
    return out;
  }

  static int _count(Map<String, dynamic> json, String field, String where) {
    final raw = json[field];
    if (raw == null) return 0;
    if (raw is! int || raw < 0) throw FormatException('Merge $where "$field" must be a non-negative int');
    return raw;
  }

  static int _randomState(Map<String, dynamic> json, String where) {
    final raw = json['random'];
    if (raw is! int || raw < 1 || raw > 0xFFFFFFFF) {
      throw FormatException('Merge $where "random" is out of range');
    }
    return raw;
  }

  MergeState _copy({
    List<int>? tiles,
    int? score,
    int? moves,
    int? randomState,
    int? undosUsed,
    bool? keepGoing,
    bool? finished,
    Object? spawned = _unset,
    Set<int>? merged,
    Object? previous = _unset,
  }) =>
      MergeState._(
        seed: seed,
        size: size,
        tiles: tiles ?? this.tiles,
        score: score ?? this.score,
        moves: moves ?? this.moves,
        randomState: randomState ?? this.randomState,
        undosUsed: undosUsed ?? this.undosUsed,
        keepGoing: keepGoing ?? this.keepGoing,
        finished: finished ?? this.finished,
        spawned: identical(spawned, _unset) ? this.spawned : spawned as int?,
        merged: merged ?? this.merged,
        previous: identical(previous, _unset) ? this.previous : previous as MergeSnapshot?,
      );

  static const Object _unset = Object();
}
