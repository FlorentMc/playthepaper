import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/puzzle_id.dart';

import '_common.dart';
import '_engine_checks.dart';

/// Validates a content tree. This is the publishing trust boundary: nothing
/// reaches the web host unless this exits 0.
///
///   dart run tool/validate.dart content [--strict]
///
/// Checks: index lists exactly the edition files present; every edition is
/// complete and every referenced puzzle file exists, parses, matches its id
/// and date; every puzzle passes its game engine's validation; news puzzles
/// in an edition do not leak one another's answers; Daily Word answers are in
/// the shipped guess list. With --strict, orphan puzzle files are errors.
void main(List<String> args) {
  if (args.isEmpty) fail('usage: dart run tool/validate.dart <content dir> [--strict]');
  final root = args.first;
  final strict = args.contains('--strict');
  final errors = <String>[];
  final warnings = <String>[];

  final indexFile = File('$root/index.json');
  if (!indexFile.existsSync()) fail('missing $root/index.json');
  late ContentIndex index;
  try {
    index = ContentIndex.fromJson(readJsonFile(indexFile.path));
  } on FormatException catch (e) {
    fail('index.json: ${e.message}');
  }

  final editionFiles = Directory('$root/editions')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
      .toSet();
  final listed = index.dates.map(formatDate).toSet();
  for (final d in listed.difference(editionFiles)) {
    errors.add('index lists $d but editions/$d.json is missing');
  }
  for (final d in editionFiles.difference(listed)) {
    errors.add('editions/$d.json exists but is not in index.json');
  }
  if (formatDate(index.latest) != (index.dates.isEmpty ? '' : formatDate(index.dates.last))) {
    errors.add('index.latest ${formatDate(index.latest)} is not the last listed date');
  }

  final words6 = File('assets/dictionaries/words6_en.txt').existsSync()
      ? File('assets/dictionaries/words6_en.txt').readAsLinesSync().map((w) => w.trim().toUpperCase()).toSet()
      : <String>{};
  if (words6.isEmpty) warnings.add('assets/dictionaries/words6_en.txt not found; Daily Word answers not checked against it');

  final referenced = <String>{};
  final puzzleCache = <String, PuzzleRecord?>{};

  PuzzleRecord? loadPuzzle(PuzzleId id, String where) {
    final key = id.toString();
    if (puzzleCache.containsKey(key)) return puzzleCache[key];
    final f = File('$root/puzzles/$key.json');
    PuzzleRecord? record;
    if (!f.existsSync()) {
      errors.add('$where references missing puzzle $key');
    } else {
      try {
        record = PuzzleRecord.fromJson(readJsonFile(f.path));
        if (record.id != id) {
          errors.add('puzzles/$key.json contains id ${record.id}');
          record = null;
        } else {
          final problem = checkPuzzleWithEngine(record);
          if (problem != null) {
            errors.add('puzzles/$key.json: $problem');
          }
          if (record.game == GameKind.word && words6.isNotEmpty) {
            final answer = record.reveal['answer'];
            if (answer is! String || !words6.contains(answer)) {
              errors.add('puzzles/$key.json: answer is not in the shipped guess list');
            }
          }
        }
      } on FormatException catch (e) {
        errors.add('puzzles/$key.json: ${e.message}');
      }
    }
    puzzleCache[key] = record;
    return record;
  }

  for (final d in editionFiles.toList()..sort()) {
    final path = '$root/editions/$d.json';
    EditionManifest m;
    try {
      m = EditionManifest.fromJson(readJsonFile(path));
    } on FormatException catch (e) {
      errors.add('editions/$d.json: ${e.message}');
      continue;
    }
    if (m.dateString != d) errors.add('editions/$d.json declares date ${m.dateString}');
    if (!m.isComplete) errors.add('editions/$d.json is incomplete (needs 9 puzzles and 3 stories)');
    final seen = <PuzzleId>{};
    for (final id in m.puzzles) {
      if (!seen.add(id)) errors.add('editions/$d.json lists $id twice');
      referenced.add(id.toString());
      final record = loadPuzzle(id, 'editions/$d.json');
      if (record?.storyId != null && m.story(record!.storyId!) == null) {
        errors.add('editions/$d.json: puzzle $id references story "${record.storyId}" that is not in the edition');
      }
    }
    final storyIds = m.stories.map((s) => s.id).toList();
    if (storyIds.toSet().length != storyIds.length) errors.add('editions/$d.json has duplicate story ids');
    for (final s in m.stories) {
      if (!s.url.startsWith('https://')) errors.add('editions/$d.json: story ${s.id} url must be https');
    }
    for (final storyId in m.seeds.keys) {
      if (m.story(storyId) == null) errors.add('editions/$d.json: seeds reference unknown story "$storyId"');
    }
    PuzzleRecord? recordOf(GameKind g) {
      final id = m.puzzleFor(g);
      return id == null ? null : puzzleCache[id.toString()];
    }
    try {
      errors.addAll(seedChecks(m, recordOf).map((e) => 'editions/$d.json: $e'));
    } on FormatException catch (e) {
      errors.add('editions/$d.json: seed checks could not run: ${e.message}');
    }
  }

  final puzzleFiles = Directory('$root/puzzles')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
      .toSet();
  for (final p in puzzleFiles.difference(referenced).toList()..sort()) {
    if (PuzzleId.tryParse(p) == null) {
      errors.add('puzzles/$p.json has a malformed name');
    } else {
      (strict ? errors : warnings).add('puzzles/$p.json is not referenced by any edition');
    }
  }

  for (final w in warnings) {
    stdout.writeln('warning: $w');
  }
  for (final e in errors) {
    stdout.writeln('error: $e');
  }
  stdout.writeln('${editionFiles.length} editions, ${puzzleFiles.length} puzzle files, '
      '${errors.length} errors, ${warnings.length} warnings');
  exit(errors.isEmpty ? 0 : 1);
}
