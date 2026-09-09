import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/engines/target/target.dart';

import '_common.dart';

/// Generates the daily Target file for a date range.
///
///   dart run tool/gen_target.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of `target-<date>`, so a
/// date always yields the same tiles and target. Existing files are kept
/// unless `--force` is given. Every written file is re-read and re-parsed
/// with the engine, which proves the reveal expression reaches the target
/// under the rules.
void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseArgs(args);
  } on ArgumentError catch (e) {
    fail('${e.message}\nusage: dart run tool/gen_target.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final from = options['from'], to = options['to'], out = options['out'];
  if (from == null || to == null || out == null) {
    fail('usage: dart run tool/gen_target.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final fromDate = parseDate(from), toDate = parseDate(to);
  if (toDate.isBefore(fromDate)) fail('--to must not be before --from');
  final force = options['force'] == 'true';
  Directory(out).createSync(recursive: true);

  final generator = TargetGenerator();
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
    final puzzle = _verify(path, record);
    final ms = clock.elapsedMilliseconds;
    if (ms > slowest) slowest = ms;
    stdout.writeln(
      '$dateText  ${record.id}  ${puzzle.tiles.join(' ')} → ${puzzle.target}  '
      '${puzzle.solution.numbers.length} tiles · ${puzzle.solution.text} · ${ms}ms',
    );
    written++;
  }
  stdout.writeln(
    '$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s total, slowest ${slowest}ms',
  );
}

TargetPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record.id != expected.id) fail('$path: id mismatch');
  final puzzle = TargetPuzzle.parse(record.payload, record.reveal);
  if (puzzle.toPayload().toString() != expected.payload.toString() ||
      puzzle.toReveal().toString() != expected.reveal.toString()) {
    fail('$path: re-parsed puzzle differs from the generated one');
  }
  if (!TargetSearch(puzzle.tiles).isReachable(puzzle.target)) fail('$path: the target is not reachable');
  return puzzle;
}
