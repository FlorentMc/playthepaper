import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/engines/loop/loop.dart';

import '_common.dart';

/// Generates the daily Loop puzzle for a date range.
///
///   dart run tool/gen_loop.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of `loop-<date>`, so a
/// date always yields the same puzzle. Existing files are kept unless
/// `--force` is given. Every written file is re-read and re-validated with
/// the engine.
void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseArgs(args, defaults: const {'out': 'content/puzzles'});
  } on ArgumentError catch (e) {
    fail('${e.message}\nusage: dart run tool/gen_loop.dart --from YYYY-MM-DD --to YYYY-MM-DD [--out <dir>] [--force]');
  }
  final from = options['from'];
  final to = options['to'];
  if (from == null || to == null) {
    fail('usage: dart run tool/gen_loop.dart --from YYYY-MM-DD --to YYYY-MM-DD [--out <dir>] [--force]');
  }
  final fromDate = parseDate(from);
  final toDate = parseDate(to);
  if (toDate.isBefore(fromDate)) fail('--to must not be before --from');
  final force = options['force'] == 'true';
  final outDir = Directory(options['out']!)..createSync(recursive: true);

  final generator = LoopGenerator();
  final total = Stopwatch()..start();
  var written = 0;
  var skipped = 0;
  for (final date in dateRange(fromDate, toDate)) {
    final dateText = formatDate(date);
    final path = '${outDir.path}${Platform.pathSeparator}loop-$dateText-en-v1.json';
    if (File(path).existsSync() && !force) {
      stdout.writeln('$dateText  kept');
      skipped++;
      continue;
    }
    final clock = Stopwatch()..start();
    final record = generator.generate(date);
    if (record.id.toString() != 'loop-$dateText-en-v1') fail('unexpected id ${record.id} for $dateText');
    writeJsonFile(path, record.toJson());
    final puzzle = _verify(path, record);
    final steps = LoopSolver.deduce(puzzle.grid, puzzle.clues, List.filled(puzzle.grid.edgeCount, LoopSolver.unknown))!.steps;
    stdout.writeln(
      '$dateText  ${puzzle.clueCount} clues, loop of ${puzzle.lineCount}, $steps look-ahead steps, ${clock.elapsedMilliseconds}ms',
    );
    written++;
  }
  stdout.writeln('$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

LoopPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record != expected) fail('$path: re-read record differs from the generated one');
  return LoopPuzzle.parse(record.payload, record.reveal);
}
