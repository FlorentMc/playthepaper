import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/engines/regions/regions.dart';

import '_common.dart';

/// Generates the daily Regions board for a date range.
///
///   dart run tool/gen_regions.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of `regions-<date>`, so
/// a date always yields the same board. Existing files are kept unless
/// `--force` is given. Every written file is re-read and re-validated with
/// the engine.
void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseArgs(args, defaults: {'out': 'content/puzzles'});
  } on ArgumentError catch (e) {
    fail('${e.message}\nusage: dart run tool/gen_regions.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final from = options['from'], to = options['to'];
  if (from == null || to == null) {
    fail('usage: dart run tool/gen_regions.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final DateTime fromDate, toDate;
  try {
    fromDate = parseDate(from);
    toDate = parseDate(to);
  } on FormatException catch (e) {
    fail(e.message);
  }
  if (toDate.isBefore(fromDate)) fail('--to must not be before --from');
  final force = options['force'] == 'true';
  final outDir = Directory(options['out']!)..createSync(recursive: true);
  final generator = RegionsGenerator();
  final total = Stopwatch()..start();
  var written = 0;
  var skipped = 0;

  for (final date in dateRange(fromDate, toDate)) {
    final dateText = formatDate(date);
    final clock = Stopwatch()..start();
    final record = generator.generate(date);
    final path = '${outDir.path}${Platform.pathSeparator}${record.id}.json';
    if (File(path).existsSync() && !force) {
      stdout.writeln('$dateText  kept ${record.id}');
      skipped++;
      continue;
    }
    writeJsonFile(path, record.toJson());
    final puzzle = _verify(path, record);
    final rating = RegionsGrader.grade(puzzle.grid, puzzle.givens);
    stdout.writeln(
      '$dateText  ${record.id}  ${puzzle.givenCount} givens · ${puzzle.grid.regionCount} regions · '
      '${rating.hiddenSingles + rating.lockedSteps} reasoning steps · ${clock.elapsedMilliseconds}ms',
    );
    written++;
  }
  stdout.writeln('$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

RegionsPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record != expected) throw StateError('$path: re-read record differs from the generated one');
  return RegionsPuzzle.parse(record.payload, record.reveal);
}
