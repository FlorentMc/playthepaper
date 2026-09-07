import 'dart:convert';
import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/edition_clock.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/engines/sudoku/sudoku.dart';

/// Generates the three daily sudoku files for a date range.
///
///   dart run tool/gen_sudoku.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]
///
/// The seed for each puzzle is a stable FNV-1a hash of
/// `sudoku-<date>-<difficulty>`, so a date always yields the same puzzle.
/// Existing files are kept unless `--force` is given. Every written file is
/// re-read and re-validated with the engine.
void main(List<String> args) {
  final options = _parse(args);
  if (options == null) {
    stderr.writeln('usage: dart run tool/gen_sudoku.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
    exitCode = 64;
    return;
  }
  final outDir = Directory(options.out)..createSync(recursive: true);
  final total = Stopwatch()..start();
  var written = 0;
  var skipped = 0;

  for (var date = options.from; !date.isAfter(options.to); date = date.add(const Duration(days: 1))) {
    final dateText = EditionClock.formatDate(date);
    final parts = <String>[];
    for (final difficulty in Difficulty.values) {
      final id = PuzzleId(game: GameKind.sudoku, date: date, difficulty: difficulty);
      final file = File('${outDir.path}${Platform.pathSeparator}$id.json');
      if (file.existsSync() && !options.force) {
        parts.add('${difficulty.slug} kept');
        skipped++;
        continue;
      }
      final clock = Stopwatch()..start();
      final puzzle = SudokuGenerator.generate(seed: SudokuGenerator.seedFor(dateText, difficulty), difficulty: difficulty);
      final record = PuzzleRecord(
        id: id,
        locale: 'en-GB',
        contentVersion: 1,
        scoringVersion: 1,
        payload: puzzle.toPayload(),
        reveal: puzzle.toReveal(),
      );
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n');
      _verify(file, id, difficulty, puzzle);
      parts.add('${difficulty.slug} ${puzzle.givenCount} givens ${clock.elapsedMilliseconds}ms');
      written++;
    }
    stdout.writeln('$dateText  ${parts.join(' · ')}');
  }
  stdout.writeln('$written written, $skipped kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

void _verify(File file, PuzzleId id, Difficulty difficulty, SudokuPuzzle expected) {
  final record = PuzzleRecord.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  if (record.id != id) throw StateError('${file.path}: id mismatch');
  final puzzle = SudokuPuzzle.parse(record.payload, record.reveal);
  if (puzzle.givensString != expected.givensString || puzzle.solutionString != expected.solutionString) {
    throw StateError('${file.path}: re-parsed puzzle differs from the generated one');
  }
  final grade = SudokuGrader.grade(puzzle.givens);
  if (grade.difficulty != difficulty) {
    throw StateError('${file.path}: graded ${grade.difficulty.slug}, expected ${difficulty.slug}');
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
