import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/engines/crossword/crossword_generator.dart';
import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';

/// Generates one Mini Crossword per date from the hand-written clue bank.
///
///   dart run tool/gen_crossword.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]
///
/// A thin wrapper over [CrosswordGenerator]: a date always yields the same
/// puzzle for the same bank and the same earlier puzzles in the output
/// directory, which are read back as history. The summary line counts the
/// answers repeated from the previous [CrosswordGenerator.recentDays] days.
const _bankPath = 'content_src/crossword/clues.json';
const _dictionaryPath = 'tool/data/enable1.txt';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final from = EditionClock.parseDate(options['from']!);
  final to = EditionClock.parseDate(options['to']!);
  final outDir = Directory(options['out']!);
  final force = options.containsKey('force');
  if (to.isBefore(from)) _fail('--to must not be before --from');
  await outDir.create(recursive: true);

  final bank = _loadBank();
  final CrosswordGenerator generator;
  try {
    generator = CrosswordGenerator(bank: bank, dictionary: _loadDictionary());
  } on FormatException catch (e) {
    _fail(e.message);
  }
  stdout.writeln(
    'Bank: ${bank.entries.length} answers '
    '(${[3, 4, 5].map((n) => '$n-letter: ${bank.byLength[n]?.length ?? 0}').join(', ')})',
  );

  for (var d = from.subtract(Duration(days: generator.historyDays)); d.isBefore(from); d = d.add(const Duration(days: 1))) {
    final existing = _readExisting(outDir, d);
    if (existing != null) generator.remember(d, existing);
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
      generator.remember(date, existing);
      skipped++;
      stdout.writeln('$dateText  skipped (exists)');
      continue;
    }

    final result = generator.generate(date);
    if (result == null) {
      for (var t = 0; t < crosswordTemplates.length; t++) {
        attempts[t]++;
      }
      failed++;
      stderr.writeln('$dateText  FAILED: no template could be filled');
      continue;
    }
    for (final t in result.templatesTried) {
      attempts[t]++;
    }
    successes[result.templateIndex]++;

    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(result.record.toJson())}\n');
    generated++;
    repeatsTotal += result.repeats;
    final repeatNote = result.repeats == 0 ? '' : '  repeats ${result.repeats}';
    stdout.writeln(
      '$dateText  template ${result.templateIndex} ${crosswordTemplates[result.templateIndex].join('/')}$repeatNote  ${result.answers.join(' ')}',
    );
  }

  stdout.writeln('');
  stdout.writeln(
    'Generated $generated, skipped $skipped, failed $failed, '
    'answers repeated from the previous ${generator.recentDays} days: $repeatsTotal',
  );
  for (var t = 0; t < crosswordTemplates.length; t++) {
    if (attempts[t] == 0) continue;
    final pct = (100 * successes[t] / attempts[t]).toStringAsFixed(0);
    stdout.writeln('template ${t.toString().padLeft(2)} ${crosswordTemplates[t].join('/')}  ${successes[t]}/${attempts[t]} ($pct%)');
  }
  if (failed > 0) exit(1);
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

Set<String> _loadDictionary() {
  final file = File(_dictionaryPath);
  if (!file.existsSync()) _fail('Dictionary not found at $_dictionaryPath');
  return file.readAsLinesSync().map((w) => w.trim().toUpperCase()).toSet();
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
