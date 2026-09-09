// Generates Letters puzzles, one per date, from the ENABLE word list filtered
// by the 50k frequency list. Deterministic per date.
//
//   dart run tool/gen_letters.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]

import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/engines/letters/letters.dart';

/// A generator over the word lists in [dataDir] (`enable1.txt`, `en_50k.txt`).
LettersGenerator loadGenerator(Directory dataDir) {
  final enable = File('${dataDir.path}/enable1.txt').readAsLinesSync().map((l) => l.trim()).toSet();
  final rankedWords = File(
    '${dataDir.path}/en_50k.txt',
  ).readAsLinesSync().map((l) => l.trim().split(RegExp(r'\s+')).first).toList();
  return LettersGenerator(
    pool: LettersGenerator.buildPool(enable: enable, rankedWords: rankedWords),
  );
}

Set<String>? existingLetters(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final record = PuzzleRecord.fromJson(json);
    return LettersPuzzle.parse(record.payload, record.reveal).letters;
  } on FormatException {
    return null;
  }
}

void main(List<String> args) {
  String? from;
  String? to;
  var out = 'content/puzzles';
  var force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--from':
        from = args[++i];
      case '--to':
        to = args[++i];
      case '--out':
        out = args[++i];
      case '--force':
        force = true;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }
  if (from == null || to == null) {
    stderr.writeln('Usage: dart run tool/gen_letters.dart --from YYYY-MM-DD --to YYYY-MM-DD [--out DIR] [--force]');
    exit(2);
  }
  final start = EditionClock.parseDate(from);
  final end = EditionClock.parseDate(to);
  if (end.isBefore(start)) {
    stderr.writeln('--to is before --from');
    exit(2);
  }

  final scriptDir = File.fromUri(Platform.script).parent;
  final generator = loadGenerator(Directory('${scriptDir.path}/data'));
  stdout.writeln('Pool: ${generator.pool.length} words, ${generator.pangramCandidates.length} pangram candidates');

  final outDir = Directory(out)..createSync(recursive: true);
  final existing = <String, File>{};
  for (final entity in outDir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final m = RegExp(r'^letters-(\d{4}-\d{2}-\d{2})-en-v1\.json$').firstMatch(name);
    if (m == null) continue;
    existing[m.group(1)!] = entity;
  }

  var written = 0;
  var skipped = 0;
  var failed = 0;
  for (var date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
    final dateText = EditionClock.formatDate(date);
    if (existing.containsKey(dateText) && !force) {
      final letters = existingLetters(existing[dateText]!);
      if (letters != null) generator.markUsed(letters);
      stdout.writeln('$dateText  skipped, exists');
      skipped++;
      continue;
    }
    final record = generator.generate(date);
    if (record == null) {
      stderr.writeln('$dateText  FAILED: no letter set satisfied the constraints');
      failed++;
      continue;
    }
    final puzzle = LettersPuzzle.parse(record.payload, record.reveal);
    File(
      '${outDir.path}/${record.id}.json',
    ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n');
    written++;
    stdout.writeln(
      '$dateText  ${puzzle.center} + ${puzzle.outer}  ${puzzle.answers.length} answers  '
      '${puzzle.pangrams.length} pangram${puzzle.pangrams.length == 1 ? '' : 's'}  maxScore ${puzzle.maxScore}',
    );
  }
  stdout.writeln('Written $written, skipped $skipped, failed $failed');
  if (failed > 0) exit(1);
}
