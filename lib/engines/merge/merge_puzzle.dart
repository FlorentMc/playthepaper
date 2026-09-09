import 'merge_rules.dart';

/// A validated daily challenge. The seed fixes the two opening tiles and the
/// whole spawn sequence, so every player gets the same game and a saved game
/// resumes exactly where it stopped.
///
/// Payload: `{"seed": 123456, "size": 4}`. Reveal: `{}` — there is no answer
/// to hide, only a board to play.
class MergePuzzle {
  /// Validates [seed] and [size] and works out the opening board. Throws
  /// [FormatException] when the size is out of range, the seed is not a
  /// 32-bit value the generator can use, or the seed does not open a
  /// playable board: two tiles, each a 2 or a 4, in different cells, with a
  /// move available.
  factory MergePuzzle({required int seed, int size = 4}) {
    MergeRules.checkSize(size);
    if (seed < 1 || seed > 0xFFFFFFFF) {
      throw FormatException('Merge seed must be between 1 and 4294967295: $seed');
    }
    final tiles = MergeRules.opening(MergeRandom(seed), size);
    final filled = <int>[];
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i] != 0) filled.add(i);
    }
    if (filled.length != 2) {
      throw FormatException('Merge seed $seed opens with ${filled.length} tiles, not 2');
    }
    for (final i in filled) {
      if (tiles[i] != 2 && tiles[i] != 4) {
        throw FormatException('Merge seed $seed opens with a ${tiles[i]} tile');
      }
    }
    if (!MergeRules.hasMove(tiles, size)) {
      throw FormatException('Merge seed $seed opens with no move available');
    }
    return MergePuzzle._(seed, size, List<int>.unmodifiable(tiles));
  }

  const MergePuzzle._(this.seed, this.size, this.openingTiles);

  static MergePuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawSeed = payload['seed'];
    if (rawSeed is! int) throw const FormatException('Merge payload is missing "seed"');
    final rawSize = payload['size'];
    if (rawSize is! int) throw const FormatException('Merge payload is missing "size"');
    if (reveal.isNotEmpty) {
      throw FormatException('Merge reveal must be empty, not ${reveal.keys.toList()}');
    }
    return MergePuzzle(seed: rawSeed, size: rawSize);
  }

  final int seed;
  final int size;

  /// The board every player starts from, two tiles on an empty grid.
  final List<int> openingTiles;

  int get cellCount => size * size;

  Map<String, dynamic> toPayload() => {'seed': seed, 'size': size};

  Map<String, dynamic> toReveal() => <String, dynamic>{};
}
