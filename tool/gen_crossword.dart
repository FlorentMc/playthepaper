import 'dart:convert';
import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/edition_clock.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/engines/crossword/crossword_generator.dart';
import 'package:daypencil/engines/crossword/crossword_puzzle.dart';

/// Generates one Mini Crossword per date from the hand-written clue bank.
///
///   dart run tool/gen_crossword.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]
///
/// The seed is the FNV-1a hash of `crossword-<date>`, so a date always
/// yields the same puzzle for the same bank and the same earlier puzzles in
/// the output directory. Answers from the previous [_hardDays] days are
/// never reused; answers from the previous [_recentDays] days are used only
/// when nothing fresher fits: candidates are tried least-used first, up to
/// [_candidates] fills are tried per template and the one whose answers
/// were used least is kept. A fill that shares more than [_maxShared]
/// answers with any puzzle of the previous [_historyDays] days is rejected.
/// The summary line counts the repeats.
const _bankPath = 'content_src/crossword/clues.json';
const _dictionaryPath = 'tool/data/enable1.txt';
const _recentDays = 30;
const _hardDays = 3;
const _historyDays = 400;
const _maxShared = 5;
const _candidates = 6;

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final from = EditionClock.parseDate(options['from']!);
  final to = EditionClock.parseDate(options['to']!);
  final outDir = Directory(options['out']!);
  final force = options.containsKey('force');
  if (to.isBefore(from)) _fail('--to must not be before --from');
  await outDir.create(recursive: true);

  final bank = _loadBank();
  _checkDictionary(bank);
  stdout.writeln(
    'Bank: ${bank.entries.length} answers '
    '(${[3, 4, 5].map((n) => '$n-letter: ${bank.byLength[n]?.length ?? 0}').join(', ')})',
  );

  final history = <DateTime, Set<String>>{};
  for (var d = from.subtract(const Duration(days: _historyDays)); d.isBefore(from); d = d.add(const Duration(days: 1))) {
    final existing = _readExisting(outDir, d);
    if (existing != null) history[d] = existing;
  }

  final attempts = List<int>.filled(crosswordTemplates.length, 0);
  final successes = List<int>.filled(crosswordTemplates.length, 0);
  var generated = 0, skipped = 0, failed = 0, repeatsTotal = 0;

  for (var date = from; !date.isAfter(to); date = date.add(const Duration(days: 1))) {
    final dateText = EditionClock.formatDate(date);
    final id = PuzzleId(game: GameKind.crossword, date: date);
    final file = File('${outDir.path}/$id.json');

    if (file.existsSync() && !force) {
      final existing = _readExisting(outDir, date);
      if (existing == null) _fail('$dateText: existing ${file.path} is not a valid crossword');
      history[date] = existing;
      skipped++;
      stdout.writeln('$dateText  skipped (exists)');
      continue;
    }

    final seed = fnv1a('crossword-$dateText');
    final start = seed % crosswordTemplates.length;
    final usage = _usage(history, date, _recentDays);
    final banned = _recentAnswers(history, date, _hardDays);
    CrosswordFill? fill;
    int? templateIndex;
    for (var k = 0; k < crosswordTemplates.length && fill == null; k++) {
      final t = (start + k) % crosswordTemplates.length;
      attempts[t]++;
      var bestWear = 0;
      for (var r = 0; r < _candidates; r++) {
        final candidate = fillGrid(
          crosswordTemplates[t],
          bank,
          SeededRandom(seed + k * _candidates + r),
          used: banned,
          usage: usage,
        );
        if (candidate == null) {
          if (r == 0) break;
          continue;
        }
        final answers = candidate.answers.values.toSet();
        if (!_isNovel(answers, history, date)) continue;
        final wear = answers.fold(0, (sum, w) => sum + (usage[w] ?? 0));
        if (fill == null || wear < bestWear) {
          fill = candidate;
          bestWear = wear;
        }
        if (wear == 0) break;
      }
      if (fill != null) {
        successes[t]++;
        templateIndex = t;
      }
    }

    if (fill == null) {
      failed++;
      stderr.writeln('$dateText  FAILED: no template could be filled');
      continue;
    }

    final parts = buildRecordParts(fill, bank, SeededRandom(seed ^ 0x9E3779B9));
    final record = PuzzleRecord(
      id: id,
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      dictionaryVersion: 'enable1-2026-09',
      payload: parts.payload,
      reveal: parts.reveal,
    );
    final json = const JsonEncoder.withIndent('  ').convert(record.toJson());
    final reparsed = PuzzleRecord.fromJson(jsonDecode(json) as Map<String, dynamic>);
    final puzzle = CrosswordPuzzle.parse(reparsed.payload, reparsed.reveal);
    final answers = answersOf(puzzle);
    if (answers.toSet().length != answers.length) _fail('$dateText: duplicate answer in fill');
    if (!answers.every((a) => fill!.answers.containsValue(a))) _fail('$dateText: solution does not match fill');

    file.writeAsStringSync('$json\n');
    history[date] = answers.toSet();
    generated++;
    final repeats = answers.where(usage.containsKey).length;
    repeatsTotal += repeats;
    final repeatNote = repeats == 0 ? '' : '  repeats $repeats';
    stdout.writeln(
      '$dateText  template $templateIndex ${crosswordTemplates[templateIndex!].join('/')}$repeatNote  ${answers.join(' ')}',
    );
  }

  stdout.writeln('');
  stdout.writeln(
    'Generated $generated, skipped $skipped, failed $failed, '
    'answers repeated from the previous $_recentDays days: $repeatsTotal',
  );
  for (var t = 0; t < crosswordTemplates.length; t++) {
    if (attempts[t] == 0) continue;
    final pct = (100 * successes[t] / attempts[t]).toStringAsFixed(0);
    stdout.writeln('template ${t.toString().padLeft(2)} ${crosswordTemplates[t].join('/')}  ${successes[t]}/${attempts[t]} ($pct%)');
  }
  if (failed > 0) exit(1);
}

/// A fill is novel when it shares at most [_maxShared] answers with every
/// puzzle of the previous [_historyDays] days.
bool _isNovel(Set<String> answers, Map<DateTime, Set<String>> history, DateTime date) {
  for (var d = 1; d <= _historyDays; d++) {
    final past = history[date.subtract(Duration(days: d))];
    if (past != null && answers.intersection(past).length > _maxShared) return false;
  }
  return true;
}

/// How many times each answer appeared in the [days] before [date].
Map<String, int> _usage(Map<DateTime, Set<String>> history, DateTime date, int days) {
  final out = <String, int>{};
  for (var d = 1; d <= days; d++) {
    for (final w in history[date.subtract(Duration(days: d))] ?? const <String>{}) {
      out[w] = (out[w] ?? 0) + 1;
    }
  }
  return out;
}

Set<String> _recentAnswers(Map<DateTime, Set<String>> history, DateTime date, int days) {
  final out = <String>{};
  for (var d = 1; d <= days; d++) {
    final past = history[date.subtract(Duration(days: d))];
    if (past != null) out.addAll(past);
  }
  return out;
}

Set<String>? _readExisting(Directory outDir, DateTime date) {
  final file = File('${outDir.path}/${PuzzleId(game: GameKind.crossword, date: date)}.json');
  if (!file.existsSync()) return null;
  try {
    final record = PuzzleRecord.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    return answersOf(CrosswordPuzzle.parse(record.payload, record.reveal)).toSet();
  } on FormatException {
    return null;
  }
}

CrosswordBank _loadBank() {
  final file = File(_bankPath);
  if (!file.existsSync()) _fail('Clue bank not found at $_bankPath');
  return CrosswordBank.fromJson(jsonDecode(file.readAsStringSync()));
}

void _checkDictionary(CrosswordBank bank) {
  final file = File(_dictionaryPath);
  if (!file.existsSync()) _fail('Dictionary not found at $_dictionaryPath');
  final words = file.readAsLinesSync().map((w) => w.trim().toUpperCase()).toSet();
  final missing = bank.entries.where((e) => !words.contains(e.answer)).map((e) => e.answer).toList();
  if (missing.isNotEmpty) _fail('Bank answers missing from ENABLE: ${missing.join(', ')}');
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) _fail('Unexpected argument: $a');
    final name = a.substring(2);
    if (name == 'force') {
      out[name] = 'true';
    } else if (i + 1 < args.length) {
      out[name] = args[++i];
    } else {
      _fail('Missing value for --$name');
    }
  }
  for (final required in ['from', 'to', 'out']) {
    if (!out.containsKey(required)) {
      _fail('Usage: dart run tool/gen_crossword.dart --from YYYY-MM-DD --to YYYY-MM-DD --out DIR [--force]');
    }
  }
  return out;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(2);
}
