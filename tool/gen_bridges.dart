import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/engines/bridges/bridges.dart';

import '_common.dart';

/// Generates the daily Bridges (Hashiwokakero) puzzle for a date range.
///
///   dart run tool/gen_bridges.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of `bridges-<date>`, so a
/// date always yields the same puzzle. Existing files are kept unless
/// `--force` is given. Every written file is re-read and re-parsed with the
/// engine, which proves the rules, the unique solution and the rating.
void main(List<String> args) {
  final Map<String, String> options;
  try {
    options = parseArgs(args, defaults: const {'out': 'content/puzzles'});
  } on ArgumentError catch (e) {
    fail('${e.message}\n$usage');
  }
  final from = options['from'];
  final to = options['to'];
  if (from == null || to == null) fail(usage);
  final fromDate = parseDate(from);
  final toDate = parseDate(to);
  if (toDate.isBefore(fromDate)) fail('--to must not be before --from');
  final force = options['force'] == 'true';
  final outDir = Directory(options['out']!)..createSync(recursive: true);

  final generator = BridgesGenerator();
  final total = Stopwatch()..start();
  var written = 0;
  var skipped = 0;
  var slowest = 0;
  for (final date in dateRange(fromDate, toDate)) {
    final dateText = formatDate(date);
    final path = '${outDir.path}${Platform.pathSeparator}bridges-$dateText-en-v1.json';
    if (File(path).existsSync() && !force) {
      stdout.writeln('$dateText  kept');
      skipped++;
      continue;
    }
    final clock = Stopwatch()..start();
    final record = generator.generate(date);
    if (record.id.toString() != 'bridges-$dateText-en-v1') fail('unexpected id ${record.id} for $dateText');
    writeJsonFile(path, record.toJson());
    final puzzle = _verify(path, record);
    final ms = clock.elapsedMilliseconds;
    if (ms > slowest) slowest = ms;
    final doubles = puzzle.solution.where((n) => n == 2).length;
    stdout.writeln(
      '$dateText  ${record.id}  ${puzzle.islandCount} islands, ${puzzle.bridgeCount} bridges '
      '($doubles double), ${BridgesSolver.rate(puzzle.layout).name}, ${ms}ms',
    );
    written++;
  }
  stdout.writeln(
    '$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s total, slowest ${slowest}ms',
  );
}

const String usage =
    'usage: dart run tool/gen_bridges.dart --from YYYY-MM-DD --to YYYY-MM-DD [--out <dir>] [--force]';

/// Re-reads the written file and rebuilds the puzzle from it. Parsing alone
/// re-checks every rule and re-proves the unique solution.
BridgesPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record.id != expected.id) fail('$path: id mismatch');
  final puzzle = BridgesPuzzle.parse(record.payload, record.reveal);
  if (jsonEncode(puzzle.toPayload()) != jsonEncode(expected.payload) ||
      jsonEncode(puzzle.toReveal()) != jsonEncode(expected.reveal)) {
    fail('$path: re-parsed puzzle differs from the generated one');
  }
  if (BridgesSolver.rate(puzzle.layout) != BridgesRating.medium) {
    fail('$path: puzzle is not rated medium');
  }
  final islands = puzzle.islandCount;
  if (islands < BridgesGenerator.minIslands || islands > BridgesGenerator.maxIslands) {
    fail('$path: $islands islands is outside the daily range');
  }
  return puzzle;
}
