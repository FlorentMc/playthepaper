import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';

import '_common.dart';

/// Assembles the content tree from generated classics and evergreen templates.
///
///   dart run tool/build_content.dart --from 2026-09-01 --to 2026-12-31 [--content content] [--src content_src]
///
/// For every date in the range:
///   * the four classic puzzle files must already exist (run the gen_* tools first);
///   * if no edition manifest exists, or the existing one is evergreen, an
///     evergreen template is stamped onto the date (round robin by day index),
///     its three news puzzles are written with dated ids, and the manifest is
///     written with kind "evergreen";
///   * an existing "news" manifest is never touched.
/// Finally index.json is rewritten from the manifests present.
void main(List<String> args) {
  final opts = parseArgs(args, defaults: {'content': 'content', 'src': 'content_src'});
  final from = parseDate(opts['from'] ?? fail('--from required'));
  final to = parseDate(opts['to'] ?? fail('--to required'));
  final content = opts['content']!;
  final src = opts['src']!;

  final templates = _loadTemplates('$src/evergreen');
  if (templates.isEmpty) fail('no evergreen templates in $src/evergreen');

  var stamped = 0, kept = 0;
  for (final date in dateRange(from, to)) {
    final ds = formatDate(date);
    final classics = _classicIds(date);
    for (final id in classics) {
      if (!File('$content/puzzles/$id.json').existsSync()) {
        fail('missing classic puzzle $content/puzzles/$id.json (run the gen_* tools first)');
      }
    }

    final manifestPath = '$content/editions/$ds.json';
    if (File(manifestPath).existsSync()) {
      final existing = EditionManifest.fromJson(readJsonFile(manifestPath));
      if (existing.kind == EditionKind.news) {
        kept++;
        continue;
      }
    }

    final dayIndex = date.difference(DateTime.utc(2026, 1, 1)).inDays;
    final template = templates[dayIndex % templates.length];
    final newsIds = <PuzzleId>[];
    final stories = <Map<String, dynamic>>[];
    for (final game in GameKind.newsOrder) {
      final spec = template.puzzles[game.slug] ?? fail('${template.slug} lacks a ${game.slug} puzzle');
      final id = PuzzleId(game: game, date: date);
      final story = template.stories.firstWhere((s) => s['game'] == game.slug,
          orElse: () => fail('${template.slug} lacks a ${game.slug} story'));
      final storyId = '${template.slug}-${game.slug}';
      final record = {
        'id': id.toString(),
        'game': game.slug,
        'editionDate': ds,
        'locale': 'en-GB',
        'contentVersion': 1,
        'scoringVersion': 1,
        'payload': spec['payload'],
        'reveal': spec['reveal'],
        'storyId': storyId,
        'sources': spec['sources'] ?? [],
      };
      PuzzleRecord.fromJson(record);
      writeJsonFile('$content/puzzles/$id.json', record);
      newsIds.add(id);
      stories.add({...story, 'id': storyId});
    }

    final manifest = {
      'date': ds,
      'kind': 'evergreen',
      'label': template.label,
      'version': 1,
      'puzzles': [...classics.map((i) => i.toString()), ...newsIds.map((i) => i.toString())],
      'stories': stories,
    };
    final parsed = EditionManifest.fromJson(manifest);
    if (!parsed.isComplete) fail('assembled edition $ds is incomplete');
    writeJsonFile(manifestPath, manifest);
    stamped++;
  }

  final dates = Directory('$content/editions')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.json'))
      .map((n) => n.substring(0, n.length - 5))
      .toList()
    ..sort();
  writeJsonFile('$content/index.json', {'dates': dates, 'latest': dates.last});
  stdout.writeln('editions: $stamped stamped evergreen, $kept news kept, ${dates.length} in index (${dates.first} → ${dates.last})');
}

List<PuzzleId> _classicIds(DateTime date) => [
      PuzzleId(game: GameKind.word, date: date),
      for (final d in Difficulty.values) PuzzleId(game: GameKind.sudoku, date: date, difficulty: d),
      PuzzleId(game: GameKind.letters, date: date),
      PuzzleId(game: GameKind.crossword, date: date),
    ];

class _Template {
  _Template(this.slug, this.label, this.stories, this.puzzles);
  final String slug;
  final String label;
  final List<Map<String, dynamic>> stories;
  final Map<String, Map<String, dynamic>> puzzles;
}

List<_Template> _loadTemplates(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) {
    final json = readJsonFile(f.path);
    final slug = json['slug'] as String? ?? fail('${f.path}: missing slug');
    final label = json['label'] as String? ?? fail('${f.path}: missing label');
    final stories = (json['stories'] as List? ?? fail('${f.path}: missing stories')).cast<Map<String, dynamic>>();
    final puzzles = (json['puzzles'] as Map<String, dynamic>? ?? fail('${f.path}: missing puzzles'))
        .map((k, v) => MapEntry(k, v as Map<String, dynamic>));
    return _Template(slug, label, stories, puzzles);
  }).toList();
}
