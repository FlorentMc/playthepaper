import 'dart:convert';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
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

/// An entry forced into the grid from one of the day's stories. The answer
/// need not be in the bank; it must appear as a whole word in [excerpt].
class CrosswordSeed {
  CrosswordSeed({required this.answer, required this.clue, required this.storyId, required this.excerpt}) {
    if (!RegExp(r'^[A-Z]{3,5}$').hasMatch(answer)) {
      throw FormatException('Crossword seed answer must be 3 to 5 letters A-Z: "$answer"');
    }
    if (clue.trim().isEmpty) throw FormatException('Crossword seed $answer needs a clue');
    if (storyId.isEmpty) throw FormatException('Crossword seed $answer needs a storyId');
    if (!RegExp('\\b$answer\\b', caseSensitive: false).hasMatch(excerpt)) {
      throw FormatException('Crossword seed $answer does not appear as a word in its excerpt');
    }
  }

  final String answer;
  final String clue;
  final String storyId;
  final String excerpt;

  int get length => answer.length;
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
/// puzzle. Entries in [fixed] are written before the search starts and kept
/// as given. Returns null when no fill is found within [maxNodes] steps.
CrosswordFill? fillGrid(
  List<String> grid,
  CrosswordBank bank,
  SeededRandom random, {
  Set<String> used = const {},
  Map<String, int> usage = const {},
  Map<CrosswordEntry, String> fixed = const {},
  int maxNodes = 5000,
}) {
  final size = grid.length;
  final entries = deriveEntries(grid);
  final cells = List<int>.filled(size * size, 0);
  final chosen = <CrosswordEntry, String>{};
  final inPuzzle = <String>{};
  for (final e in entries) {
    final w = fixed[e];
    if (w == null) continue;
    if (w.length != e.length) throw ArgumentError('$w does not fit ${e.label} (${e.length} letters)');
    for (var i = 0; i < e.length; i++) {
      final have = cells[e.cells[i]];
      if (have != 0 && have != w.codeUnitAt(i)) throw ArgumentError('$w conflicts with a crossing fixed entry at ${e.label}');
      cells[e.cells[i]] = w.codeUnitAt(i);
    }
    chosen[e] = w;
    inPuzzle.add(w);
  }
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
/// answer with [random]. Entries whose answer is in [seeds] take the seed's
/// clue and story instead, and are listed in `reveal.seeded` in entry order.
({Map<String, dynamic> payload, Map<String, dynamic> reveal}) buildRecordParts(
  CrosswordFill fill,
  CrosswordBank bank,
  SeededRandom random, {
  List<CrosswordSeed> seeds = const [],
  String? teaser,
}) {
  final byAnswer = {for (final e in bank.entries) e.answer: e};
  final seedByAnswer = {for (final s in seeds) s.answer: s};
  final seeded = <CrosswordSeedReveal>[];
  final clued = deriveEntries(fill.grid).map((e) {
    final answer = fill.answers[e]!;
    final seed = seedByAnswer[answer];
    if (seed != null) {
      seeded.add(CrosswordSeedReveal(label: e.label, storyId: seed.storyId, excerpt: seed.excerpt));
      return e.withClue(seed.clue, storyId: seed.storyId);
    }
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
      if (teaser != null && seeded.isNotEmpty) 'teaser': teaser,
    },
    reveal: {
      'solution': fill.solution,
      if (seeded.isNotEmpty) 'seeded': seeded.map((s) => s.toJson()).toList(),
    },
  );
}

/// Every way to give each of [seeds], in order, a distinct entry of its
/// length whose crossings agree with the seeds already placed. Entries are
/// tried in grid order, so the result is deterministic.
List<Map<CrosswordEntry, String>> seedAssignments(List<CrosswordEntry> entries, List<CrosswordSeed> seeds) {
  final out = <Map<CrosswordEntry, String>>[];
  final cells = <int, int>{};
  final placed = <CrosswordEntry, String>{};

  void place(int i) {
    if (i == seeds.length) {
      out.add(Map.unmodifiable(placed));
      return;
    }
    final seed = seeds[i];
    for (final e in entries) {
      if (e.length != seed.length || placed.containsKey(e)) continue;
      final written = <int>[];
      var ok = true;
      for (var k = 0; k < e.length && ok; k++) {
        final cell = e.cells[k];
        final ch = seed.answer.codeUnitAt(k);
        final have = cells[cell];
        if (have == null) {
          cells[cell] = ch;
          written.add(cell);
        } else if (have != ch) {
          ok = false;
        }
      }
      if (ok) {
        placed[e] = seed.answer;
        place(i + 1);
        placed.remove(e);
      }
      for (final c in written) {
        cells.remove(c);
      }
    }
  }

  place(0);
  return out;
}

/// The outcome of [CrosswordGenerator.generate].
class CrosswordGeneration {
  const CrosswordGeneration({
    required this.record,
    required this.answers,
    required this.seeds,
    required this.templateIndex,
    required this.templatesTried,
    required this.repeats,
  });

  final PuzzleRecord record;

  /// Every answer in entry order.
  final List<String> answers;

  /// The seeds that made it into the grid, in the order they were given.
  final List<CrosswordSeed> seeds;

  /// Index into [crosswordTemplates] of the pattern used.
  final int templateIndex;

  /// The template indices tried, in order, ending with [templateIndex].
  final List<int> templatesTried;

  /// Answers also used within the previous [CrosswordGenerator.recentDays] days.
  final int repeats;

  int get seedsPlaced => seeds.length;
}

/// Produces one Mini Crossword record per date from the bank, optionally
/// forcing story seeds into the grid.
///
/// The PRNG seed is the FNV-1a hash of `crossword-<date>`, so a date always
/// yields the same puzzle for the same bank, seeds and [history]. Answers
/// from the previous [hardDays] days are never reused from the bank; answers
/// from the previous [recentDays] days are used only when nothing fresher
/// fits: candidates are tried least-used first, up to [candidates] fills are
/// tried per template and the one whose answers were used least is kept. A
/// fill that shares more than [maxShared] answers with any puzzle of the
/// previous [historyDays] days is rejected.
///
/// With seeds, each template (in date-seeded order) is tried with every
/// assignment of the seeds to distinct entries of their length, and the rest
/// is filled from the bank. When no template takes them all, the last seed
/// is dropped and the search restarts, down to an unseeded puzzle.
class CrosswordGenerator {
  CrosswordGenerator({
    required this.bank,
    required Set<String> dictionary,
    Map<DateTime, Set<String>> history = const {},
    this.recentDays = 30,
    this.hardDays = 3,
    this.historyDays = 400,
    this.maxShared = 5,
    this.candidates = 6,
  }) : history = Map.of(history) {
    final missing = bank.entries.where((e) => !dictionary.contains(e.answer)).map((e) => e.answer).toList();
    if (missing.isNotEmpty) throw FormatException('Bank answers missing from the dictionary: ${missing.join(', ')}');
  }

  final CrosswordBank bank;

  /// Answers of every earlier puzzle by date. Each generation is added.
  final Map<DateTime, Set<String>> history;
  final int recentDays;
  final int hardDays;
  final int historyDays;
  final int maxShared;
  final int candidates;

  /// Records an existing puzzle's answers so later dates avoid them.
  void remember(DateTime date, Set<String> answers) => history[date] = answers;

  /// Generates the puzzle for [date], or null when no template can be
  /// filled. [teaser] is written to the payload when at least one seed is
  /// placed; the record's `storyId` is the first placed seed's story.
  CrosswordGeneration? generate(DateTime date, {List<CrosswordSeed> seeds = const [], String? teaser, int version = 1}) {
    final answersSeen = <String>{};
    for (final s in seeds) {
      if (!answersSeen.add(s.answer)) throw FormatException('Crossword seeds repeat ${s.answer}');
    }
    final seed = _seedFor(date);
    final start = seed % crosswordTemplates.length;
    final usage = _usage(date);
    final banned = _recentAnswers(date);

    for (var n = seeds.length; n >= 0; n--) {
      final active = seeds.sublist(0, n);
      final tried = <int>[];
      for (var k = 0; k < crosswordTemplates.length; k++) {
        final t = (start + k) % crosswordTemplates.length;
        tried.add(t);
        final grid = crosswordTemplates[t];
        for (final fixed in seedAssignments(deriveEntries(grid), active)) {
          final fill = _bestFill(grid, seed + k * candidates, fixed, date, usage, banned);
          if (fill != null) return _finish(fill, date, active, teaser, version, t, List.unmodifiable(tried));
        }
      }
    }
    return null;
  }

  static int _seedFor(DateTime date) => fnv1a('crossword-${EditionClock.formatDate(date)}');

  /// The least-worn novel fill of [grid] with [fixed] entries over up to
  /// [candidates] PRNG seeds from [base]; null when the first attempt fails.
  CrosswordFill? _bestFill(
    List<String> grid,
    int base,
    Map<CrosswordEntry, String> fixed,
    DateTime date,
    Map<String, int> usage,
    Set<String> banned,
  ) {
    CrosswordFill? best;
    var bestWear = 0;
    for (var r = 0; r < candidates; r++) {
      final candidate = fillGrid(grid, bank, SeededRandom(base + r), used: banned, usage: usage, fixed: fixed);
      if (candidate == null) {
        if (r == 0) break;
        continue;
      }
      final answers = candidate.answers.values.toSet();
      if (!_isNovel(answers, date)) continue;
      final wear = answers.fold(0, (sum, w) => sum + (usage[w] ?? 0));
      if (best == null || wear < bestWear) {
        best = candidate;
        bestWear = wear;
      }
      if (wear == 0) break;
    }
    return best;
  }

  CrosswordGeneration _finish(
    CrosswordFill fill,
    DateTime date,
    List<CrosswordSeed> seeds,
    String? teaser,
    int version,
    int templateIndex,
    List<int> tried,
  ) {
    final parts = buildRecordParts(fill, bank, SeededRandom(_seedFor(date) ^ 0x9E3779B9), seeds: seeds, teaser: teaser);
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.crossword, date: date, version: version),
      locale: 'en-GB',
      contentVersion: version,
      scoringVersion: 1,
      dictionaryVersion: 'enable1-2026-09',
      payload: parts.payload,
      reveal: parts.reveal,
      storyId: seeds.isEmpty ? null : seeds.first.storyId,
    );
    final reparsed = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    final puzzle = CrosswordPuzzle.parse(reparsed.payload, reparsed.reveal);
    final answers = answersOf(puzzle);
    if (answers.toSet().length != answers.length) throw StateError('Duplicate answer in fill for ${record.id}');
    if (!answers.every(fill.answers.containsValue)) throw StateError('Solution does not match fill for ${record.id}');
    if (puzzle.seeded.length != seeds.length) throw StateError('Seeds lost in fill for ${record.id}');
    final usage = _usage(date);
    history[date] = answers.toSet();
    return CrosswordGeneration(
      record: record,
      answers: answers,
      seeds: List.unmodifiable(seeds),
      templateIndex: templateIndex,
      templatesTried: tried,
      repeats: answers.where(usage.containsKey).length,
    );
  }

  /// A fill is novel when it shares at most [maxShared] answers with every
  /// puzzle of the previous [historyDays] days.
  bool _isNovel(Set<String> answers, DateTime date) {
    for (var d = 1; d <= historyDays; d++) {
      final past = history[date.subtract(Duration(days: d))];
      if (past != null && answers.intersection(past).length > maxShared) return false;
    }
    return true;
  }

  /// How many times each answer appeared in the [recentDays] before [date].
  Map<String, int> _usage(DateTime date) {
    final out = <String, int>{};
    for (var d = 1; d <= recentDays; d++) {
      for (final w in history[date.subtract(Duration(days: d))] ?? const <String>{}) {
        out[w] = (out[w] ?? 0) + 1;
      }
    }
    return out;
  }

  Set<String> _recentAnswers(DateTime date) {
    final out = <String>{};
    for (var d = 1; d <= hardDays; d++) {
      final past = history[date.subtract(Duration(days: d))];
      if (past != null) out.addAll(past);
    }
    return out;
  }
}
