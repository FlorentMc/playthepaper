import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/engines/kakuro/kakuro.dart';

import '_common.dart';

/// Generates the daily kakuro file for a date range.
///
///   dart run tool/gen_kakuro.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of `kakuro-<date>`, so a
/// date always yields the same board. Existing files are kept unless
/// `--force` is given. Every written file is re-read and re-parsed with the
/// engine, which proves the clues, the solution and its uniqueness.
void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseArgs(args, defaults: {'out': 'content/puzzles'});
  } on ArgumentError catch (e) {
    fail('${e.message}\nusage: dart run tool/gen_kakuro.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final from = options['from'];
  final to = options['to'];
  if (from == null || to == null) {
    fail('usage: dart run tool/gen_kakuro.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final DateTime fromDate, toDate;
  try {
    fromDate = parseDate(from);
    toDate = parseDate(to);
  } on FormatException catch (e) {
    fail(e.message);
  }
  if (toDate.isBefore(fromDate)) fail('--to must not be before --from');
  final outDir = options['out']!;
  final force = options['force'] == 'true';
  final generator = KakuroGenerator();
  final total = Stopwatch()..start();
  var written = 0;
  var kept = 0;

  for (final date in dateRange(fromDate, toDate)) {
    final dateText = formatDate(date);
    final path = '$outDir${Platform.pathSeparator}kakuro-$dateText-en-v1.json';
    if (File(path).existsSync() && !force) {
      stdout.writeln('$dateText  kept');
      kept++;
      continue;
    }
    final clock = Stopwatch()..start();
    final record = generator.generate(date);
    writeJsonFile(path, record.toJson());
    final puzzle = _verify(path, record);
    stdout.writeln(
      '$dateText  ${puzzle.grid.whiteCount} cells, ${puzzle.runs.length} runs, '
      '${KakuroSolver.deduce(puzzle.grid).rounds} passes, ${clock.elapsedMilliseconds}ms',
    );
    written++;
  }
  stdout.writeln('$written written, $kept kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

KakuroPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record != expected) throw StateError('$path: re-read record differs from the generated one');
  final puzzle = KakuroPuzzle.parse(record.payload, record.reveal);
  if (!KakuroGenerator.isAcceptable(puzzle.grid)) throw StateError('$path: puzzle fails the generator checks');
  return puzzle;
}
