/// The rules of the sliding tile game: how a line moves, when tiles merge,
/// where a new tile appears, and when the board is stuck. Pure Dart, used by
/// the app, the generator and the tests.
library;

/// The four ways a board can be pushed.
enum MergeDirection {
  left('left', 'Left'),
  right('right', 'Right'),
  up('up', 'Up'),
  down('down', 'Down');

  const MergeDirection(this.slug, this.label);

  final String slug;
  final String label;

  static MergeDirection fromSlug(String slug) {
    for (final d in values) {
      if (d.slug == slug) return d;
    }
    throw FormatException('Unknown merge direction: $slug');
  }
}

/// A 32-bit xorshift generator whose whole state is one integer, so a saved
/// game resumes on exactly the sequence it left off on. Only shifts and
/// exclusive-ors, so it gives the same numbers on the web as on a phone.
class MergeRandom {
  MergeRandom(int state) : _state = normalise(state);

  static const int _fallback = 0x9E3779B9;

  int _state;

  /// Folds [seed] into the 1..0xFFFFFFFF range xorshift needs.
  static int normalise(int seed) {
    final s = seed & 0xFFFFFFFF;
    return s == 0 ? _fallback : s;
  }

  int get state => _state;

  int next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  int nextInt(int bound) {
    if (bound < 1) throw RangeError.value(bound, 'bound', 'must be positive');
    return next() % bound;
  }
}

/// One line after it has been pushed towards its front.
class MergeLine {
  const MergeLine({required this.tiles, required this.gained, required this.merged});

  final List<int> tiles;

  /// The score the merges in this line scored.
  final int gained;

  /// Positions in [tiles] that were formed by a merge.
  final List<int> merged;
}

/// A whole board after a push.
class MergeSlide {
  const MergeSlide({required this.tiles, required this.gained, required this.merged, required this.changed});

  final List<int> tiles;
  final int gained;

  /// Board indices that were formed by a merge.
  final Set<int> merged;

  /// False when nothing moved and nothing merged; such a move spawns nothing.
  final bool changed;
}

class MergeRules {
  const MergeRules._();

  static const int minSize = 3;
  static const int maxSize = 8;

  /// The tile the daily challenge is named after.
  static const int winningTile = 2048;

  /// A new tile is a 4 this often, in a hundred; otherwise it is a 2.
  static const int fourPercent = 10;

  static void checkSize(int size) {
    if (size < minSize || size > maxSize) {
      throw FormatException('Merge size must be between $minSize and $maxSize: $size');
    }
  }

  /// True for a value a cell may hold: a power of two, four or more once
  /// merged, and 2 or 4 when spawned.
  static bool isTile(int value) => value >= 2 && value <= 0x40000000 && (value & (value - 1)) == 0;

  /// The rank of a tile: 1 for 2, 2 for 4, 11 for 2048.
  static int rankOf(int value) {
    var rank = 0;
    var v = value;
    while (v > 1) {
      v >>= 1;
      rank++;
    }
    return rank;
  }

  static List<int> emptyCells(List<int> tiles) {
    final out = <int>[];
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i] == 0) out.add(i);
    }
    return out;
  }

  static int bestTile(List<int> tiles) {
    var best = 0;
    for (final v in tiles) {
      if (v > best) best = v;
    }
    return best;
  }

  /// The cells of line [line] in the order they are pushed, front first.
  static List<int> lineIndices(int size, MergeDirection direction, int line) {
    return List<int>.generate(size, (k) {
      switch (direction) {
        case MergeDirection.left:
          return line * size + k;
        case MergeDirection.right:
          return line * size + (size - 1 - k);
        case MergeDirection.up:
          return k * size + line;
        case MergeDirection.down:
          return (size - 1 - k) * size + line;
      }
    }, growable: false);
  }

  /// Pushes one line towards index 0. Tiles slide over gaps, and two equal
  /// neighbours merge into their sum; a tile that has just merged does not
  /// merge again on the same push, so `2 2 2 2` becomes `4 4` and `2 2 4`
  /// becomes `4 4`, never `8`.
  static MergeLine slideLine(List<int> line) {
    final packed = <int>[];
    for (final v in line) {
      if (v != 0) packed.add(v);
    }
    final tiles = <int>[];
    final merged = <int>[];
    var gained = 0;
    var i = 0;
    while (i < packed.length) {
      if (i + 1 < packed.length && packed[i] == packed[i + 1]) {
        final sum = packed[i] * 2;
        merged.add(tiles.length);
        tiles.add(sum);
        gained += sum;
        i += 2;
      } else {
        tiles.add(packed[i]);
        i += 1;
      }
    }
    while (tiles.length < line.length) {
      tiles.add(0);
    }
    return MergeLine(tiles: tiles, gained: gained, merged: merged);
  }

  /// Pushes the whole board one step in [direction].
  static MergeSlide slide(List<int> tiles, int size, MergeDirection direction) {
    if (tiles.length != size * size) {
      throw FormatException('Merge board must have ${size * size} cells, not ${tiles.length}');
    }
    final next = List<int>.of(tiles, growable: false);
    final mergedCells = <int>{};
    var gained = 0;
    var changed = false;
    for (var line = 0; line < size; line++) {
      final cells = lineIndices(size, direction, line);
      final before = [for (final c in cells) tiles[c]];
      final after = slideLine(before);
      for (var k = 0; k < size; k++) {
        if (after.tiles[k] != before[k]) changed = true;
        next[cells[k]] = after.tiles[k];
      }
      for (final k in after.merged) {
        mergedCells.add(cells[k]);
      }
      gained += after.gained;
    }
    return MergeSlide(tiles: next, gained: gained, merged: mergedCells, changed: changed);
  }

  /// True when some push would change the board: an empty cell, or two equal
  /// tiles side by side.
  static bool hasMove(List<int> tiles, int size) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final v = tiles[r * size + c];
        if (v == 0) return true;
        if (c + 1 < size && tiles[r * size + c + 1] == v) return true;
        if (r + 1 < size && tiles[(r + 1) * size + c] == v) return true;
      }
    }
    return false;
  }

  /// Puts one new tile in a random empty cell of [tiles], which it edits in
  /// place, and returns its index; -1 when the board is full.
  static int spawn(List<int> tiles, MergeRandom random) {
    final empty = emptyCells(tiles);
    if (empty.isEmpty) return -1;
    final at = empty[random.nextInt(empty.length)];
    tiles[at] = random.nextInt(100) < fourPercent ? 4 : 2;
    return at;
  }

  /// The two tiles a game opens with, drawn from [random].
  static List<int> opening(MergeRandom random, int size) {
    checkSize(size);
    final tiles = List<int>.filled(size * size, 0);
    spawn(tiles, random);
    spawn(tiles, random);
    return tiles;
  }

  /// `5432` as `5,432`, for the score line.
  static String groupDigits(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
