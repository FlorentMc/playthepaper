import 'crossword_puzzle.dart';

/// One answer in the clue bank with its alternative clues.
class BankEntry {
  const BankEntry({required this.answer, required this.clues});

  final String answer;
  final List<String> clues;

  int get length => answer.length;
}

/// The hand-written clue bank, grouped by answer length.
class CrosswordBank {
  CrosswordBank(List<BankEntry> entries)
      : entries = List.unmodifiable(entries),
        byLength = {
          for (final e in entries) e.length: [],
        } {
    for (final e in entries) {
      byLength[e.length]!.add(e);
    }
  }

  final List<BankEntry> entries;
  final Map<int, List<BankEntry>> byLength;

  /// Parses `[{"answer": "CAT", "clues": ["Feline pet"]}, ...]`. Checks the
  /// shape and uniqueness only; dictionary membership is the caller's job.
  static CrosswordBank fromJson(Object? json) {
    if (json is! List) throw const FormatException('Clue bank must be a JSON array');
    final seen = <String>{};
    final entries = <BankEntry>[];
    for (var i = 0; i < json.length; i++) {
      final item = json[i];
      if (item is! Map) throw FormatException('Clue bank item $i is not an object');
      final answer = item['answer'];
      final clues = item['clues'];
      if (answer is! String || !RegExp(r'^[A-Z]{3,5}$').hasMatch(answer)) {
        throw FormatException('Clue bank item $i has an invalid answer: $answer');
      }
      if (!seen.add(answer)) throw FormatException('Clue bank repeats $answer');
      if (clues is! List || clues.isEmpty || clues.any((c) => c is! String || c.trim().isEmpty)) {
        throw FormatException('Clue bank entry $answer needs a non-empty list of clue strings');
      }
      entries.add(BankEntry(answer: answer, clues: clues.cast<String>()));
    }
    return CrosswordBank(entries);
  }
}

/// 5×5 block patterns with 180° rotational symmetry and every entry at least
/// three letters. Every template is checked with [deriveEntries] at load.
final List<List<String>> crosswordTemplates = List.unmodifiable(
  [
    ['.....', '.....', '.....', '.....', '.....'],
    ['#....', '.....', '.....', '.....', '....#'],
    ['....#', '.....', '.....', '.....', '#....'],
    ['##...', '.....', '.....', '.....', '...##'],
    ['...##', '.....', '.....', '.....', '##...'],
    ['#....', '#....', '.....', '....#', '....#'],
    ['....#', '....#', '.....', '#....', '#....'],
    ['#...#', '.....', '.....', '.....', '#...#'],
    ['##...', '#....', '.....', '....#', '...##'],
    ['...##', '....#', '.....', '#....', '##...'],
    ['##...', '##...', '.....', '...##', '...##'],
    ['...##', '...##', '.....', '##...', '##...'],
  ].map((t) {
    deriveEntries(t);
    if (!isRotationallySymmetric(t)) throw StateError('Template is not symmetric: $t');
    return List<String>.unmodifiable(t);
  }),
);

bool isRotationallySymmetric(List<String> grid) {
  final n = grid.length;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (grid[r][c] != grid[n - 1 - r][n - 1 - c]) return false;
    }
  }
  return true;
}

/// 32-bit FNV-1a over the UTF-8 bytes of [text].
int fnv1a(String text) {
  var hash = 0x811C9DC5;
  for (final unit in text.codeUnits) {
    hash ^= unit & 0xFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Deterministic PRNG (mulberry32) so a seed yields the same puzzle on
/// every platform and Dart version.
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  int _next() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = (_mul(t ^ (t >>> 15), t | 1)) & 0xFFFFFFFF;
    t = (t ^ (t + _mul(t ^ (t >>> 7), t | 61))) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  static int _mul(int a, int b) {
    final aHi = a >>> 16, aLo = a & 0xFFFF;
    final bHi = b >>> 16, bLo = b & 0xFFFF;
    return ((aLo * bLo) + (((aHi * bLo + aLo * bHi) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }

  /// A uniform integer in `[0, max)`.
  int nextInt(int max) => _next() % max;

  List<T> shuffled<T>(Iterable<T> items) {
    final list = items.toList();
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

/// A filled template: the solution rows and the answer chosen per entry.
class CrosswordFill {
  const CrosswordFill({required this.grid, required this.solution, required this.answers});

  final List<String> grid;
  final List<String> solution;
  final Map<CrosswordEntry, String> answers;
}

/// Fills [grid] from [bank] by backtracking. One of the longest entries is
/// filled first, so different seeds anchor on different words; after that
/// the most constrained entry is filled next. Candidates matching the
/// current letter pattern are tried least-used first by [usage] (answers
/// missing from it count as unused), shuffled by [random] within a usage
/// count, so well-worn answers are chosen only when nothing fresher fits.
/// Answers in [used] are never chosen and no answer repeats within a
/// puzzle. Returns null when no fill is found within [maxNodes] steps.
CrosswordFill? fillGrid(
  List<String> grid,
  CrosswordBank bank,
  SeededRandom random, {
  Set<String> used = const {},
  Map<String, int> usage = const {},
  int maxNodes = 5000,
}) {
  final size = grid.length;
  final entries = deriveEntries(grid);
  final cells = List<int>.filled(size * size, 0);
  final chosen = <CrosswordEntry, String>{};
  final inPuzzle = <String>{};
  final ordered = <int, List<String>>{};
  for (final e in entries) {
    ordered.putIfAbsent(e.length, () {
      final buckets = <int, List<String>>{};
      for (final b in bank.byLength[e.length] ?? const <BankEntry>[]) {
        if (used.contains(b.answer)) continue;
        buckets.putIfAbsent(usage[b.answer] ?? 0, () => []).add(b.answer);
      }
      final counts = buckets.keys.toList()..sort();
      return [for (final c in counts) ...random.shuffled(buckets[c]!)];
    });
  }
  var nodes = 0;

  List<String> candidates(CrosswordEntry e) {
    final out = <String>[];
    final slots = e.cells;
    for (final w in ordered[e.length]!) {
      if (inPuzzle.contains(w)) continue;
      var ok = true;
      for (var i = 0; i < slots.length; i++) {
        final have = cells[slots[i]];
        if (have != 0 && have != w.codeUnitAt(i)) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(w);
    }
    return out;
  }

  final longest = entries.map((e) => e.length).reduce((a, b) => a > b ? a : b);
  final anchors = entries.where((e) => e.length == longest).toList();
  final anchor = anchors[random.nextInt(anchors.length)];

  bool solve() {
    if (chosen.length == entries.length) return true;
    if (++nodes > maxNodes) return false;
    CrosswordEntry? best;
    List<String>? bestCandidates;
    if (chosen.isEmpty) {
      best = anchor;
      bestCandidates = candidates(anchor);
    } else {
      for (final e in entries) {
        if (chosen.containsKey(e)) continue;
        final c = candidates(e);
        if (c.isEmpty) return false;
        if (bestCandidates == null || c.length < bestCandidates.length) {
          best = e;
          bestCandidates = c;
        }
      }
    }
    final e = best!;
    final previous = List<int>.filled(e.length, 0);
    for (final w in bestCandidates!) {
      for (var i = 0; i < e.length; i++) {
        previous[i] = cells[e.cells[i]];
        cells[e.cells[i]] = w.codeUnitAt(i);
      }
      chosen[e] = w;
      inPuzzle.add(w);
      if (solve()) return true;
      chosen.remove(e);
      inPuzzle.remove(w);
      for (var i = 0; i < e.length; i++) {
        cells[e.cells[i]] = previous[i];
      }
      if (nodes > maxNodes) return false;
    }
    return false;
  }

  if (!solve()) return null;
  final solution = [
    for (var r = 0; r < size; r++)
      [
        for (var c = 0; c < size; c++)
          grid[r][c] == blockChar ? blockChar : String.fromCharCode(cells[r * size + c]),
      ].join(),
  ];
  return CrosswordFill(grid: grid, solution: solution, answers: Map.unmodifiable(chosen));
}

/// Builds the payload and reveal for a filled grid, picking one clue per
/// answer with [random].
({Map<String, dynamic> payload, Map<String, dynamic> reveal}) buildRecordParts(
  CrosswordFill fill,
  CrosswordBank bank,
  SeededRandom random,
) {
  final byAnswer = {for (final e in bank.entries) e.answer: e};
  final clued = deriveEntries(fill.grid).map((e) {
    final answer = fill.answers[e]!;
    final clues = byAnswer[answer]!.clues;
    return e.withClue(clues[random.nextInt(clues.length)]);
  }).toList();
  return (
    payload: {
      'size': fill.grid.length,
      'grid': fill.grid,
      'clues': {
        for (final direction in Direction.values)
          direction.name: [
            for (final e in clued)
              if (e.direction == direction) e.toJson(),
          ],
      },
    },
    reveal: {'solution': fill.solution},
  );
}
