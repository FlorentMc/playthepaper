import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/engines/nonogram/nonogram.dart';

import '_common.dart';

/// Generates one Nonogram per date from the authored picture set.
///
///   dart run tool/gen_nonogram.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// Pictures come from `content_src/nonogram/pictures.json`; the copy embedded
/// in the engine must match it exactly. Every picture is run through the
/// solver first and the ones that fail are listed with the reason. Existing
/// files are kept unless `--force` is given. Every written file is re-read
/// and re-parsed with the engine.
const _picturesPath = 'content_src/nonogram/pictures.json';

void main(List<String> args) {
  final options = parseArgs(args);
  final fromText = options['from'], toText = options['to'], out = options['out'];
  if (fromText == null || toText == null || out == null) {
    fail('usage: dart run tool/gen_nonogram.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final from = parseDate(fromText);
  final to = parseDate(toText);
  if (to.isBefore(from)) fail('--to must not be before --from');
  final force = options['force'] == 'true';

  final pictures = _loadPictures();
  final generator = NonogramGenerator(pictures: pictures);
  var failed = 0, notUnique = 0;
  for (final picture in pictures) {
    final problem = NonogramGenerator.problem(picture);
    if (problem == null) continue;
    failed++;
    if (problem.contains('solution')) notUnique++;
    stderr.writeln('picture ${picture.size}×${picture.size} "${picture.title}" rejected: $problem');
  }
  for (final size in [NonogramGenerator.smallSize, NonogramGenerator.largeSize]) {
    final total = pictures.where((p) => p.size == size).length;
    stdout.writeln('$size×$size: ${generator.passing(size).length} of $total pictures pass');
  }
  stdout.writeln('$failed rejected, $notUnique of them for not having a unique solution');

  final total = Stopwatch()..start();
  var written = 0, kept = 0;
  for (final date in dateRange(from, to)) {
    final id = PuzzleId(game: GameKind.nonogram, date: date);
    final path = '$out${Platform.pathSeparator}$id.json';
    if (File(path).existsSync() && !force) {
      stdout.writeln('${formatDate(date)}  kept');
      kept++;
      continue;
    }
    final clock = Stopwatch()..start();
    final record = generator.generate(date);
    writeJsonFile(path, record.toJson());
    final puzzle = _verify(path, record);
    stdout.writeln(
      '${formatDate(date)}  ${puzzle.width}×${puzzle.height} "${puzzle.title}" '
      '${(puzzle.fillFraction * 100).round()}% filled, ${NonogramSolver.analyse(puzzle).sweeps} sweeps, ${clock.elapsedMilliseconds}ms',
    );
    written++;
  }
  stdout.writeln('$written written, $kept kept, ${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

List<NonogramPicture> _loadPictures() {
  final file = File(_picturesPath);
  if (!file.existsSync()) fail('$_picturesPath not found; run from the project root');
  final raw = jsonDecode(file.readAsStringSync());
  if (raw is! List) fail('$_picturesPath must be a JSON list');
  final pictures = <NonogramPicture>[];
  for (final item in raw) {
    if (item is! Map) fail('$_picturesPath: every picture must be an object');
    try {
      pictures.add(NonogramPicture.fromJson(Map<String, dynamic>.from(item)));
    } on FormatException catch (e) {
      fail('$_picturesPath: ${e.message}');
    }
  }
  if (!_samePictures(pictures, nonogramPictures)) {
    fail('$_picturesPath differs from lib/engines/nonogram/nonogram_pictures.dart; update the embedded copy');
  }
  return pictures;
}

bool _samePictures(List<NonogramPicture> a, List<NonogramPicture> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].title != b[i].title || a[i].rows.join('/') != b[i].rows.join('/')) return false;
  }
  return true;
}

NonogramPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record.id != expected.id) fail('$path: id mismatch');
  final NonogramPuzzle puzzle;
  try {
    puzzle = NonogramPuzzle.parse(record.payload, record.reveal);
  } on FormatException catch (e) {
    fail('$path: ${e.message}');
  }
  if (puzzle.title != expected.payload['title'] || puzzle.picture.join() != (expected.reveal['cells'] as List).join()) {
    fail('$path: re-parsed puzzle differs from the generated one');
  }
  return puzzle;
}
