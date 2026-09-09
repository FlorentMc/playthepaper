import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues_generator.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues_puzzle.dart';

/// Writes the Five Clues puzzle files for a date range from the evergreen
/// reserve in content_src/editorial/fiveclues.
///
///   dart run tool/gen_fiveclues.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// Every reserve file is parsed first and each failure is reported. The pick
/// for a date is a stable FNV-1a hash of `fiveclues-<date>`, avoiding any
/// file used in the previous thirty days. Existing files are kept unless
/// `--force` is given. Every written file is re-read and re-parsed.
void main(List<String> args) {
  final options = _parse(args);
  if (options == null) {
    stderr.writeln('usage: dart run tool/gen_fiveclues.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
    exitCode = 64;
    return;
  }
  final generator = FiveCluesGenerator();
  stdout.writeln('Reserve: ${generator.files.length} puzzles in ${generator.reserveDir}');
  for (final problem in generator.problems) {
    stderr.writeln('reserve: $problem');
  }
  if (generator.problems.isNotEmpty) {
    stderr.writeln('${generator.problems.length} reserve file(s) failed to parse');
    exitCode = 1;
    return;
  }
  final outDir = Directory(options.out)..createSync(recursive: true);
  final total = Stopwatch()..start();
  var written = 0;
  var skipped = 0;

  for (var date = options.from; !date.isAfter(options.to); date = DateTime.utc(date.year, date.month, date.day + 1)) {
    final dateText = EditionClock.formatDate(date);
    final clock = Stopwatch()..start();
    final PuzzleRecord record;
    try {
      record = generator.generate(date);
    } on StateError catch (e) {
      stderr.writeln(e.message);
      exitCode = 1;
      return;
    }
    final file = File('${outDir.path}${Platform.pathSeparator}${record.id}.json');
    if (file.existsSync() && !options.force) {
      stdout.writeln('$dateText  kept');
      skipped++;
      continue;
    }
    final index = generator.pickFor(date);
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n');
    _verify(file, record);
    stdout.writeln('$dateText  ${generator.files[index]} · ${generator.items[index].topic} · ${clock.elapsedMilliseconds}ms');
    written++;
  }
  stdout.writeln('$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

void _verify(File file, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  if (record.id != expected.id) throw StateError('${file.path}: id mismatch');
  final puzzle = FiveCluesPuzzle.parse(record.payload, record.reveal);
  final generated = FiveCluesPuzzle.parse(expected.payload, expected.reveal);
  if (puzzle != generated || record.sources.length != expected.sources.length) {
    throw StateError('${file.path}: re-parsed puzzle differs from the generated one');
  }
}

class _Options {
  const _Options({required this.from, required this.to, required this.out, required this.force});
  final DateTime from;
  final DateTime to;
  final String out;
  final bool force;
}

_Options? _parse(List<String> args) {
  String? from, to, out;
  var force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--from':
        if (++i >= args.length) return null;
        from = args[i];
      case '--to':
        if (++i >= args.length) return null;
        to = args[i];
      case '--out':
        if (++i >= args.length) return null;
        out = args[i];
      case '--force':
        force = true;
      default:
        return null;
    }
  }
  if (from == null || to == null || out == null) return null;
  final DateTime fromDate, toDate;
  try {
    fromDate = EditionClock.parseDate(from);
    toDate = EditionClock.parseDate(to);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return null;
  }
  if (toDate.isBefore(fromDate)) {
    stderr.writeln('--to must not be before --from');
    return null;
  }
  return _Options(from: fromDate, to: toDate, out: out, force: force);
}
