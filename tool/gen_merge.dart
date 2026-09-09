import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/engines/merge/merge.dart';

import '_common.dart';

/// Generates the daily 2048 file for a date range.
///
///   dart run tool/gen_merge.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of `merge-<date>`, so a
/// date always deals the same game. Existing files are kept unless `--force`
/// is given. Every written file is re-read, re-parsed with the engine and
/// played out by the reference player, which proves the deal is the one that
/// was accepted.
void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseArgs(args);
  } on ArgumentError catch (e) {
    fail('${e.message}\nusage: dart run tool/gen_merge.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final from = options['from'], to = options['to'], out = options['out'];
  if (from == null || to == null || out == null) {
    fail('usage: dart run tool/gen_merge.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final fromDate = parseDate(from), toDate = parseDate(to);
  if (toDate.isBefore(fromDate)) fail('--to must not be before --from');
  final force = options['force'] == 'true';
  Directory(out).createSync(recursive: true);

  final generator = MergeGenerator();
  final total = Stopwatch()..start();
  var written = 0, skipped = 0, slowest = 0;
  for (final date in dateRange(fromDate, toDate)) {
    final dateText = formatDate(date);
    final clock = Stopwatch()..start();
    final record = generator.generate(date);
    final path = '$out${Platform.pathSeparator}${record.id}.json';
    if (File(path).existsSync() && !force) {
      stdout.writeln('$dateText  kept ${record.id}');
      skipped++;
      continue;
    }
    writeJsonFile(path, record.toJson());
    final run = _verify(path, record);
    final ms = clock.elapsedMilliseconds;
    if (ms > slowest) slowest = ms;
    stdout.writeln('$dateText  ${record.id}  seed ${record.payload['seed']} · $run · ${ms}ms');
    written++;
  }
  stdout.writeln(
    '$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s total, slowest ${slowest}ms',
  );
}

MergeRun _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record.id != expected.id) fail('$path: id mismatch');
  final puzzle = MergePuzzle.parse(record.payload, record.reveal);
  if (puzzle.seed != expected.payload['seed'] || puzzle.size != expected.payload['size']) {
    fail('$path: re-parsed puzzle differs from the generated one');
  }
  final run = MergeBot.play(puzzle);
  if (!MergeGenerator.accepts(run)) fail('$path: the deal does not clear the bar ($run)');
  return run;
}
