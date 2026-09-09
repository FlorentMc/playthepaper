/// Everything the line solver knows about one row or column after trying
/// every placement of its runs that agrees with the cells already decided.
/// Masks have bit `i` set for cell `i` of the line.
class LineDeduction {
  const LineDeduction({required this.filled, required this.empty, required this.placements});

  /// Cells filled in every consistent placement.
  final int filled;

  /// Cells empty in every consistent placement.
  final int empty;

  /// How many placements agree with the known cells. Zero is a contradiction.
  final int placements;

  bool get isContradiction => placements == 0;
}

/// Run arithmetic for a single line. Pure functions over bitmasks.
class NonogramLine {
  NonogramLine._();

  /// The fewest cells [clues] need: the runs plus one gap between each pair.
  static int minLength(List<int> clues) {
    if (clues.isEmpty) return 0;
    var sum = 0;
    for (final c in clues) {
      sum += c;
    }
    return sum + clues.length - 1;
  }

  /// The runs of set bits in [mask], left to right, as a clue.
  static List<int> runs(int mask, int length) {
    final out = <int>[];
    var run = 0;
    for (var i = 0; i < length; i++) {
      if (mask & (1 << i) != 0) {
        run++;
      } else if (run > 0) {
        out.add(run);
        run = 0;
      }
    }
    if (run > 0) out.add(run);
    return out;
  }

  /// Enumerates every placement of [clues] in a line of [length] that keeps
  /// the cells in [knownFilled] filled and the cells in [knownEmpty] empty,
  /// and reports what all of them agree on.
  static LineDeduction deduce({
    required int length,
    required List<int> clues,
    required int knownFilled,
    required int knownEmpty,
  }) {
    final all = (1 << length) - 1;
    var andMask = all;
    var orMask = 0;
    var count = 0;
    final tail = List<int>.filled(clues.length + 1, 0);
    for (var i = clues.length - 1; i >= 0; i--) {
      tail[i] = tail[i + 1] + clues[i] + 1;
    }

    void place(int index, int pos, int acc) {
      if (index == clues.length) {
        if (knownFilled >> pos != 0) return;
        count++;
        andMask &= acc;
        orMask |= acc;
        return;
      }
      final len = clues[index];
      final rest = tail[index + 1];
      for (var start = pos; start + len + rest <= length; start++) {
        if (start > pos && knownFilled & (1 << (start - 1)) != 0) break;
        final block = ((1 << len) - 1) << start;
        if (block & knownEmpty != 0) continue;
        final end = start + len;
        if (end < length && knownFilled & (1 << end) != 0) continue;
        place(index + 1, end + 1, acc | block);
      }
    }

    place(0, 0, 0);
    if (count == 0) return const LineDeduction(filled: 0, empty: 0, placements: 0);
    return LineDeduction(filled: andMask, empty: all & ~orMask, placements: count);
  }
}
