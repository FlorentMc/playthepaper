import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';

import '_common.dart';

/// Generates one Tangram per date from the authored figures.
///
///   dart run tool/gen_tangram.dart --from 2026-09-10 --to 2026-10-31 --out content/puzzles [--force]
///
/// Figures come from `content_src/tangram/silhouettes.json`; the copy embedded
/// in the engine must match it exactly. Every figure is checked first and the
/// ones that fail are listed with the reason. Existing files are kept unless
/// `--force` is given. Every written file is re-read and re-parsed with the
/// engine.
const _silhouettesPath = 'content_src/tangram/silhouettes.json';

void main(List<String> args) {
  final options = parseArgs(args);
  final fromText = options['from'], toText = options['to'], out = options['out'];
  if (fromText == null || toText == null || out == null) {
    fail('usage: dart run tool/gen_tangram.dart --from YYYY-MM-DD --to YYYY-MM-DD --out <dir> [--force]');
  }
  final from = parseDate(fromText);
  final to = parseDate(toText);
  if (to.isBefore(from)) fail('--to must not be before --from');
  final force = options['force'] == 'true';

  final silhouettes = _loadSilhouettes();
  final generator = TangramGenerator(silhouettes: silhouettes);
  var rejected = 0;
  for (final silhouette in silhouettes) {
    final problem = TangramGenerator.problem(silhouette);
    if (problem == null) continue;
    rejected++;
    stderr.writeln('figure "${silhouette.name}" rejected: $problem');
  }
  stdout.writeln('${generator.passing.length} of ${silhouettes.length} figures pass, $rejected rejected');

  final total = Stopwatch()..start();
  var written = 0, kept = 0;
  var slowest = 0;
  for (final date in dateRange(from, to)) {
    final id = PuzzleId(game: GameKind.tangram, date: date);
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
    slowest = clock.elapsedMilliseconds > slowest ? clock.elapsedMilliseconds : slowest;
    stdout.writeln(
      '${formatDate(date)}  "${puzzle.name}"  ${puzzle.outline.first.length} corners, '
      '${puzzle.mask.filled} samples, ${clock.elapsedMilliseconds}ms',
    );
    written++;
  }
  stdout.writeln('$written written, $kept kept, slowest ${slowest}ms, '
      '${(total.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
}

List<TangramSilhouette> _loadSilhouettes() {
  final file = File(_silhouettesPath);
  if (!file.existsSync()) fail('$_silhouettesPath not found; run from the project root');
  final raw = jsonDecode(file.readAsStringSync());
  if (raw is! List) fail('$_silhouettesPath must be a JSON list');
  final silhouettes = <TangramSilhouette>[];
  for (final item in raw) {
    if (item is! Map) fail('$_silhouettesPath: every figure must be an object');
    try {
      silhouettes.add(TangramSilhouette.fromJson(Map<String, dynamic>.from(item)));
    } on FormatException catch (e) {
      fail('$_silhouettesPath: ${e.message}');
    }
  }
  if (!_same(silhouettes, tangramSilhouettes)) {
    fail('$_silhouettesPath differs from lib/engines/tangram/tangram_silhouettes.dart; '
        'update the embedded copy');
  }
  return silhouettes;
}

bool _same(List<TangramSilhouette> a, List<TangramSilhouette> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].name != b[i].name) return false;
    if (jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) return false;
  }
  return true;
}

TangramPuzzle _verify(String path, PuzzleRecord expected) {
  final record = PuzzleRecord.fromJson(readJsonFile(path));
  if (record.id != expected.id) fail('$path: id mismatch');
  final TangramPuzzle puzzle;
  try {
    puzzle = TangramPuzzle.parse(record.payload, record.reveal);
  } on FormatException catch (e) {
    fail('$path: ${e.message}');
  }
  if (puzzle.name != expected.payload['name'] ||
      jsonEncode(puzzle.toReveal()) != jsonEncode(expected.reveal)) {
    fail('$path: re-parsed puzzle differs from the generated one');
  }
  return puzzle;
}
