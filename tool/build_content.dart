import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/engines/crossword/crossword_generator.dart';
import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:playthepaper/engines/letters/letters.dart';
import 'package:playthepaper/engines/quiz/quiz_engine.dart';
import 'package:playthepaper/engines/word/word_engine.dart';

import '_common.dart';
import '_generators.dart';
import '_share_pages.dart';

/// Assembles the content tree for a date range from edition templates.
///
///   dart run tool/build_content.dart --from 2026-09-01 --to 2026-12-31
///   dart run tool/build_content.dart --date 2026-09-08 [--news]
///
/// For every date: the template is `content_src/news/<date>.json` when it
/// exists, otherwise an evergreen template chosen by rotation. The builder
/// writes the quiz, generates the Daily Word, Letters and Mini Crossword
/// with the template's seeds, requires the Sudoku files (run gen_sudoku
/// first), writes the manifest with its `seeds` map, share pages and
/// index.json. Puzzle files are immutable: when generated content differs
/// from every existing version of that puzzle, a new version is written and
/// the manifest points at it; identical content reuses the existing id.
void main(List<String> args) {
  final opts = parseArgs(args, defaults: {'content': 'content', 'src': 'content_src', 'web': 'web/index.html'});
  final DateTime from;
  final DateTime to;
  if (opts.containsKey('date')) {
    from = to = parseDate(opts['date']!);
  } else {
    from = parseDate(opts['from'] ?? fail('--from/--to or --date required'));
    to = parseDate(opts['to'] ?? fail('--to required'));
  }
  final content = opts['content']!;
  final src = opts['src']!;
  final requireNews = opts.containsKey('news');
  final optionalFrom = opts.containsKey('optional-from') ? parseDate(opts['optional-from']!) : kOptionalGamesFrom;

  final evergreen = _loadTemplates('$src/evergreen');
  if (evergreen.isEmpty) fail('no evergreen templates in $src/evergreen');
  final generators = _Generators.load();

  // Letters never repeats a letter set and the crossword avoids recent
  // answers: seed both memories with every puzzle already on disk.
  for (final f in _puzzleFiles(content, GameKind.letters)) {
    try {
      final r = PuzzleRecord.fromJson(readJsonFile(f.path));
      generators.letters.markUsed(LettersPuzzle.parse(r.payload, r.reveal).letters);
    } on FormatException {
      continue;
    }
  }
  for (final f in _puzzleFiles(content, GameKind.crossword)) {
    try {
      final r = PuzzleRecord.fromJson(readJsonFile(f.path));
      generators.crossword.remember(r.date, answersOf(CrosswordPuzzle.parse(r.payload, r.reveal)).toSet());
    } on FormatException {
      continue;
    }
  }

  var built = 0;
  var keptNews = 0;
  for (final date in dateRange(from, to)) {
    final ds = formatDate(date);
    final newsFile = File('$src/news/$ds.json');
    if (requireNews && !newsFile.existsSync()) fail('--news given but $src/news/$ds.json does not exist');
    final _Template template;
    final EditionKind kind;
    if (newsFile.existsSync()) {
      template = _Template.fromJson(readJsonFile(newsFile.path), newsFile.path);
      kind = EditionKind.news;
    } else {
      final manifestFile = File('$content/editions/$ds.json');
      if (manifestFile.existsSync() && EditionManifest.fromJson(readJsonFile(manifestFile.path)).kind == EditionKind.news) {
        keptNews++;
        stdout.writeln('$ds  news edition kept (no template change possible without $src/news/$ds.json)');
        continue;
      }
      final dayIndex = date.difference(DateTime.utc(2026, 1, 1)).inDays;
      template = evergreen[dayIndex % evergreen.length];
      kind = EditionKind.evergreen;
    }

    final classics = <PuzzleId>[];
    final lines = <String>[];
    for (final d in Difficulty.values) {
      final id = PuzzleId(game: GameKind.sudoku, date: date, difficulty: d);
      if (!File('$content/puzzles/$id.json').existsSync()) {
        fail('missing $content/puzzles/$id.json (run gen_sudoku first)');
      }
      classics.add(id);
    }

    // Daily Word.
    final wordSeed = template.wordSeed;
    PuzzleRecord word;
    try {
      word = generators.word.generate(date, seed: wordSeed);
      lines.add('word ${wordSeed == null ? 'unseeded' : 'seeded ${wordSeed.answer}'}');
    } on FormatException catch (e) {
      fail('$ds word seed rejected: ${e.message}');
    }
    final wordId = _writeVersioned(content, word);

    // Letters, with fallback to an unseeded set when the pangram never fits.
    var lettersSeed = template.lettersSeed;
    PuzzleRecord? letters;
    if (lettersSeed != null) {
      try {
        letters = generators.letters.generate(date, seed: lettersSeed);
      } on FormatException catch (e) {
        fail('$ds letters seed rejected: ${e.message}');
      }
      if (letters == null) {
        lines.add('letters seed ${lettersSeed.pangram} yields no valid set; falling back to unseeded');
        lettersSeed = null;
      }
    }
    letters ??= generators.letters.generate(date) ?? fail('$ds letters: no letter set satisfied the constraints');
    lines.add('letters ${lettersSeed == null ? 'unseeded' : 'seeded ${lettersSeed.pangram}'}');
    final lettersId = _writeVersioned(content, letters);

    // Mini Crossword. The teaser depends on how many seeds fit, so generate
    // once to learn the count, then once more with the matching teaser.
    var generation = generators.crossword.generate(date, seeds: template.crosswordSeeds) ??
        fail('$ds crossword: no template could be filled');
    if (generation.seedsPlaced > 0) {
      generation = generators.crossword.generate(date, seeds: template.crosswordSeeds, teaser: _crosswordTeaser(generation.seedsPlaced))!;
    }
    final crossword = generation.record;
    lines.add('crossword ${template.crosswordSeeds.isEmpty ? 'unseeded' : '${generation.seedsPlaced} of ${template.crosswordSeeds.length} seeds placed'}');
    final crosswordId = _writeVersioned(content, crossword);

    // Optional games: generated logic and play puzzles, and editorial puzzles
    // from the template or the evergreen reserve. Only from [optionalFrom],
    // so editions that have already opened are never changed.
    final optionalIds = <PuzzleId>[];
    final optionalSeeds = <String, String>{};
    if (!date.isBefore(optionalFrom)) {
      for (final entry in generatedGames.entries) {
        final record = entry.value(date);
        optionalIds.add(_writeVersioned(content, record));
        lines.add('${entry.key.slug} generated');
      }
      for (final entry in editorialGames.entries) {
        final slug = entry.key.slug;
        final item = template.editorial[slug];
        final PuzzleRecord record;
        if (item != null) {
          final storyId = item['storyId'] as String?;
          record = entry.value.fromTemplate(date, item, storyId: storyId);
          if (storyId != null) optionalSeeds[slug] = storyId;
          lines.add('$slug from template${storyId == null ? '' : ' ($storyId)'}');
        } else {
          record = entry.value.generate(date);
          lines.add('$slug from reserve');
        }
        optionalIds.add(_writeVersioned(content, record));
      }
    }

    // The Quiz.
    final quizId = PuzzleId(game: GameKind.quiz, date: date);
    final quiz = PuzzleRecord(
      id: quizId,
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: template.quizPayload,
      reveal: template.quizReveal,
      sources: template.quizSources,
    );
    QuizPuzzle.parse(quiz.payload, quiz.reveal);
    final quizWrittenId = _writeVersioned(content, quiz);

    // Seeds map for the Front Page.
    final seeds = <String, List<String>>{};
    void feed(String storyId, String what) => seeds.putIfAbsent(storyId, () => []).add(what);
    final questions = template.quizPayload['questions'] as List;
    for (var i = 0; i < questions.length; i++) {
      feed((questions[i] as Map)['storyId'] as String, 'quiz:${i + 1}');
    }
    if (word.storyId != null) feed(word.storyId!, 'word');
    if (letters.storyId != null) feed(letters.storyId!, 'letters');
    for (final s in CrosswordPuzzle.parse(crossword.payload, crossword.reveal).seeded) {
      feed(s.storyId, 'crossword:${s.label}');
    }
    for (final e in optionalSeeds.entries) {
      feed(e.value, e.key);
    }
    for (final storyId in seeds.keys) {
      if (!template.stories.any((s) => s['id'] == storyId)) fail('$ds: seed references unknown story $storyId');
    }

    final manifestFile = File('$content/editions/$ds.json');
    var version = 1;
    if (manifestFile.existsSync()) {
      final old = EditionManifest.fromJson(readJsonFile(manifestFile.path));
      version = old.version;
    }
    final manifest = {
      'date': ds,
      'kind': kind.slug,
      'label': template.label,
      'version': version,
      'puzzles': [wordId, ...classics, lettersId, crosswordId, quizWrittenId, ...optionalIds].map((i) => i.toString()).toList(),
      'stories': template.stories,
      'seeds': seeds,
      if (kind == EditionKind.news) 'publishedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (manifestFile.existsSync()) {
      final old = readJsonFile(manifestFile.path);
      final same = _sameManifest(old, manifest);
      if (!same) manifest['version'] = version + 1;
      if (same) {
        stdout.writeln('$ds  unchanged (${template.slug})');
        continue;
      }
    }
    final parsed = EditionManifest.fromJson(manifest);
    if (!parsed.isComplete) fail('assembled edition $ds is incomplete');
    writeJsonFile(manifestFile.path, manifest);
    built++;
    stdout.writeln('$ds  ${kind.slug} ${template.slug}: ${lines.join('; ')}');
  }

  final dates = Directory('$content/editions')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.json'))
      .map((n) => n.substring(0, n.length - 5))
      .toList()
    ..sort();
  writeJsonFile('$content/index.json', {'dates': dates, 'latest': dates.last});
  final sharePages = writeSharePages(content, opts['web']!);
  stdout.writeln('editions: $built written, $keptNews news kept, ${dates.length} in index (${dates.first} → ${dates.last}); share pages: $sharePages written');
}

/// The first edition that carries the optional games. Earlier editions are
/// open or archived and are never rewritten.
final DateTime kOptionalGamesFrom = DateTime.utc(2026, 9, 10);

String _crosswordTeaser(int n) => switch (n) {
      1 => 'One of today\'s clues comes from the news.',
      2 => 'Two of today\'s clues come from the news.',
      3 => 'Three of today\'s clues come from the news.',
      _ => 'Four of today\'s clues come from the news.',
    };

bool _sameManifest(Map<String, dynamic> a, Map<String, dynamic> b) {
  Map<String, dynamic> strip(Map<String, dynamic> m) =>
      Map.of(m)..remove('version')..remove('publishedAt')..remove('correctionNote');
  return jsonEncode(strip(a)) == jsonEncode(strip(b));
}

/// Writes [record] as the lowest version whose content matches, creating a
/// new version when no existing file has the same payload and reveal.
PuzzleId _writeVersioned(String content, PuzzleRecord record) {
  final base = record.id;
  var version = 1;
  while (true) {
    final id = PuzzleId(game: base.game, date: base.date, language: base.language, difficulty: base.difficulty, version: version);
    final file = File('$content/puzzles/$id.json');
    final candidate = _withVersion(record, id);
    if (!file.existsSync()) {
      writeJsonFile(file.path, candidate.toJson());
      return id;
    }
    final existing = readJsonFile(file.path);
    if (_sameContent(existing, candidate.toJson())) return id;
    version++;
  }
}

bool _sameContent(Map<String, dynamic> a, Map<String, dynamic> b) {
  Map<String, dynamic> strip(Map<String, dynamic> m) => Map.of(m)..remove('id')..remove('contentVersion');
  return jsonEncode(strip(a)) == jsonEncode(strip(b));
}

PuzzleRecord _withVersion(PuzzleRecord r, PuzzleId id) => PuzzleRecord(
      id: id,
      locale: r.locale,
      contentVersion: id.version,
      scoringVersion: r.scoringVersion,
      dictionaryVersion: r.dictionaryVersion,
      payload: r.payload,
      reveal: r.reveal,
      storyId: r.storyId,
      sources: r.sources,
    );

Iterable<File> _puzzleFiles(String content, GameKind game) {
  final dir = Directory('$content/puzzles');
  if (!dir.existsSync()) return const [];
  return dir.listSync().whereType<File>().where((f) => f.uri.pathSegments.last.startsWith('${game.slug}-')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

class _Generators {
  _Generators({required this.word, required this.letters, required this.crossword});

  final WordGenerator word;
  final LettersGenerator letters;
  final CrosswordGenerator crossword;

  static _Generators load() {
    final enable = File('tool/data/enable1.txt').readAsLinesSync().map((l) => l.trim().toLowerCase()).where((l) => l.isNotEmpty).toSet();
    final ranked = File('tool/data/en_50k.txt').readAsLinesSync().map((l) => l.trim().split(RegExp(r'\s+')).first).toList();
    final rankOf = <String, int>{for (var i = 0; i < ranked.length; i++) ranked[i]: i + 1};
    final guessList = File('assets/dictionaries/words6_en.txt').readAsLinesSync().map((l) => l.trim().toUpperCase()).toSet();
    return _Generators(
      word: WordGenerator(candidates: WordGenerator.buildCandidates(enable: enable, rankOf: rankOf), guessList: guessList),
      letters: LettersGenerator(pool: LettersGenerator.buildPool(enable: enable, rankedWords: ranked)),
      crossword: CrosswordGenerator(
        bank: CrosswordBank.fromJson(jsonDecode(File('content_src/crossword/clues.json').readAsStringSync())),
        dictionary: enable.map((w) => w.toUpperCase()).toSet(),
      ),
    );
  }
}

class _Template {
  _Template({
    required this.slug,
    required this.label,
    required this.stories,
    required this.quizPayload,
    required this.quizReveal,
    required this.quizSources,
    required this.wordSeed,
    required this.lettersSeed,
    required this.crosswordSeeds,
    this.editorial = const {},
  });

  final String slug;
  final String label;
  final List<Map<String, dynamic>> stories;
  final Map<String, dynamic> quizPayload;
  final Map<String, dynamic> quizReveal;
  final List<SourceRef> quizSources;
  final WordSeed? wordSeed;
  final LettersSeed? lettersSeed;
  final List<CrosswordSeed> crosswordSeeds;

  /// Editorial items supplied by the template, by game slug.
  final Map<String, Map<String, dynamic>> editorial;

  static _Template fromJson(Map<String, dynamic> json, String path) {
    Never bad(String what) => fail('$path: $what');
    final slug = json['slug'] as String? ?? bad('missing slug');
    final label = json['label'] as String? ?? bad('missing label');
    final stories = (json['stories'] as List? ?? bad('missing stories')).cast<Map<String, dynamic>>();
    for (final s in stories) {
      Story.fromJson(s);
    }
    final quiz = json['quiz'] as Map<String, dynamic>? ?? bad('missing quiz');
    final payload = quiz['payload'] as Map<String, dynamic>? ?? bad('missing quiz.payload');
    final reveal = quiz['reveal'] as Map<String, dynamic>? ?? bad('missing quiz.reveal');
    QuizPuzzle.parse(payload, reveal);
    final sources = (quiz['sources'] as List? ?? const []).map((s) => SourceRef.fromJson(s as Map<String, dynamic>)).toList();
    final seeds = json['seeds'] as Map<String, dynamic>? ?? bad('missing seeds');

    WordSeed? wordSeed;
    final w = seeds['word'];
    if (w is Map) {
      wordSeed = WordSeed(
        answer: (w['answer'] as String).toUpperCase(),
        storyId: w['storyId'] as String,
        teaser: w['teaser'] as String,
        excerpt: w['excerpt'] as String,
      );
    }
    LettersSeed? lettersSeed;
    final l = seeds['letters'];
    if (l is Map) {
      lettersSeed = LettersSeed(
        pangram: (l['pangram'] as String).toUpperCase(),
        storyId: l['storyId'] as String,
        teaser: l['teaser'] as String,
        excerpt: l['excerpt'] as String,
      );
    }
    final crosswordSeeds = <CrosswordSeed>[];
    final c = seeds['crossword'];
    if (c is List) {
      for (final item in c) {
        final m = item as Map;
        crosswordSeeds.add(CrosswordSeed(
          answer: (m['answer'] as String).toUpperCase(),
          clue: m['clue'] as String,
          storyId: m['storyId'] as String,
          excerpt: m['excerpt'] as String,
        ));
      }
    }
    final storyIds = stories.map((s) => s['id']).toSet();
    for (final id in [wordSeed?.storyId, lettersSeed?.storyId, ...crosswordSeeds.map((s) => s.storyId)]) {
      if (id != null && !storyIds.contains(id)) bad('seed references unknown story $id');
    }
    final editorial = <String, Map<String, dynamic>>{};
    final rawEditorial = json['editorial'];
    if (rawEditorial is Map) {
      for (final e in rawEditorial.entries) {
        final game = GameKind.tryFromSlug(e.key as String);
        if (game == null || !game.isEditorial) bad('editorial section names unknown game ${e.key}');
        final item = e.value;
        if (item is! Map) bad('editorial item ${e.key} must be an object');
        final storyId = item['storyId'];
        if (storyId != null && !storyIds.contains(storyId)) bad('editorial item ${e.key} references unknown story $storyId');
        editorial[e.key as String] = Map<String, dynamic>.from(item);
      }
    }
    return _Template(
      slug: slug,
      label: label,
      stories: stories,
      quizPayload: payload,
      quizReveal: reveal,
      quizSources: sources,
      wordSeed: wordSeed,
      lettersSeed: lettersSeed,
      crosswordSeeds: crosswordSeeds,
      editorial: editorial,
    );
  }
}

List<_Template> _loadTemplates(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => _Template.fromJson(readJsonFile(f.path), f.path)).toList();
}
