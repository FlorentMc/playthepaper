import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/engines/word/word_engine.dart';

/// Generates Daily Word puzzle files for a date range.
///
///   dart run tool/gen_word.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]
///
/// Answers are common six-letter words. The schedule is a fixed shuffle of
/// the candidate list, so a date always yields the same word as long as the
/// word lists and [WordGenerator]'s filters do not change.

const enablePath = 'tool/data/enable1.txt';
const frequencyPath = 'tool/data/en_50k.txt';
const guessListPath = 'assets/dictionaries/words6_en.txt';

void main(List<String> args) {
  final options = _parseArgs(args);
  final from = EditionClock.parseDate(options['from']!);
  final to = EditionClock.parseDate(options['to']!);
  final outDir = Directory(options['out']!);
  final force = options.containsKey('force');
  if (to.isBefore(from)) _fail('--to is before --from');

  final WordGenerator generator;
  try {
    generator = loadGenerator();
  } on StateError catch (e) {
    _fail(e.message);
  }
  final candidates = generator.candidates;

  outDir.createSync(recursive: true);
  var written = 0;
  var skipped = 0;
  for (var date = from; !date.isAfter(to); date = date.add(const Duration(days: 1))) {
    final PuzzleRecord record;
    try {
      record = generator.generate(date);
    } on StateError catch (e) {
      _fail(e.message);
    }
    final file = File('${outDir.path}/${record.id}.json');
    if (file.existsSync() && !force) {
      skipped++;
      continue;
    }
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n');
    written++;
  }

  stdout.writeln(
    'Candidates: ${candidates.length} (${candidates.first} … ${candidates.last} sorted, '
    'schedule seed ${WordGenerator.scheduleSeed})',
  );
  stdout.writeln('Range: ${EditionClock.formatDate(from)} to ${EditionClock.formatDate(to)}');
  stdout.writeln('Written: $written, skipped existing: $skipped, out: ${outDir.path}');
}

/// A generator over the word lists in the repository.
WordGenerator loadGenerator() => WordGenerator(
  candidates: WordGenerator.buildCandidates(enable: _readWords(enablePath), rankOf: _readRanks(frequencyPath)),
  guessList: _readWords(guessListPath, uppercase: true),
);

Set<String> _readWords(String path, {bool uppercase = false}) {
  final file = File(path);
  if (!file.existsSync()) _fail('Missing $path');
  return {
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty) uppercase ? line.trim().toUpperCase() : line.trim().toLowerCase(),
  };
}

/// Word to 1-based rank, most frequent first. Lines are "word count".
Map<String, int> _readRanks(String path) {
  final file = File(path);
  if (!file.existsSync()) _fail('Missing $path');
  final ranks = <String, int>{};
  var rank = 0;
  for (final line in file.readAsLinesSync()) {
    final word = line.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (word.isEmpty) continue;
    rank++;
    ranks.putIfAbsent(word, () => rank);
  }
  return ranks;
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) _fail('Unexpected argument: $arg');
    final name = arg.substring(2);
    if (name == 'force') {
      options[name] = 'true';
    } else if (i + 1 < args.length) {
      options[name] = args[++i];
    } else {
      _fail('Missing value for --$name');
    }
  }
  for (final required in ['from', 'to', 'out']) {
    if (!options.containsKey(required)) {
      _fail('Usage: dart run tool/gen_word.dart --from YYYY-MM-DD --to YYYY-MM-DD --out DIR [--force]');
    }
  }
  return options;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
