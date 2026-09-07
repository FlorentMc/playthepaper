import 'dart:io';

import 'package:daypencil/content/models.dart';

import '_common.dart';

/// Copies a window of editions from `content/` into `assets/content/` so a
/// fresh install can play offline: the last [before] days and the next
/// [after] days around [today] (edition dates, UTC).
///
///   dart run tool/bundle_starter.dart [--today 2026-09-08] [--before 3] [--after 7]
void main(List<String> args) {
  final opts = parseArgs(args, defaults: {'before': '3', 'after': '7', 'content': 'content', 'assets': 'assets/content'});
  final today = opts.containsKey('today') ? parseDate(opts['today']!) : _editionToday();
  final before = int.parse(opts['before']!);
  final after = int.parse(opts['after']!);
  final content = opts['content']!;
  final assets = opts['assets']!;

  final from = DateTime.utc(today.year, today.month, today.day - before);
  final to = DateTime.utc(today.year, today.month, today.day + after);

  for (final sub in ['editions', 'puzzles']) {
    final d = Directory('$assets/$sub');
    if (d.existsSync()) d.deleteSync(recursive: true);
    d.createSync(recursive: true);
  }

  final dates = <String>[];
  var puzzles = 0;
  for (final date in dateRange(from, to)) {
    final ds = formatDate(date);
    final src = File('$content/editions/$ds.json');
    if (!src.existsSync()) continue;
    final manifest = EditionManifest.fromJson(readJsonFile(src.path));
    src.copySync('$assets/editions/$ds.json');
    for (final id in manifest.puzzles) {
      final p = File('$content/puzzles/$id.json');
      if (!p.existsSync()) fail('edition $ds references missing $id');
      p.copySync('$assets/puzzles/$id.json');
      puzzles++;
    }
    dates.add(ds);
  }
  if (dates.isEmpty) fail('no editions between ${formatDate(from)} and ${formatDate(to)} in $content');
  writeJsonFile('$assets/index.json', {'dates': dates, 'latest': dates.last});
  stdout.writeln('bundled ${dates.length} editions (${dates.first} → ${dates.last}), $puzzles puzzles into $assets');
}

DateTime _editionToday() {
  final u = DateTime.now().toUtc().subtract(const Duration(hours: 4));
  return DateTime.utc(u.year, u.month, u.day);
}
