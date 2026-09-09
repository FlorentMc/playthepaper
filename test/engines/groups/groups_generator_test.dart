import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/groups/groups.dart';
import 'package:playthepaper/engines/groups/groups_generator.dart';

import 'fixtures.dart';

void main() {
  final generator = GroupsGenerator();

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(GroupsGenerator.fnv1a(''), 0x811C9DC5);
    expect(GroupsGenerator.fnv1a('a'), 0xE40C292C);
    expect(GroupsGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(GroupsGenerator.seedFor(DateTime.utc(2026, 9, 10)), GroupsGenerator.fnv1a('groups-2026-09-10'));
  });

  test('every reserve file parses and there are at least thirty', () {
    expect(generator.problems, isEmpty);
    expect(generator.files.length, greaterThanOrEqualTo(GroupsGenerator.minReserve));
    for (final file in generator.files) {
      expect(RegExp(r'^\d{3}\.json$').hasMatch(file), isTrue, reason: file);
    }
    for (final item in generator.items) {
      expect(item.editorNotes, isNotNull, reason: '${item.topic}: editor notes');
      expect(item.sources.length, greaterThanOrEqualTo(GroupsPuzzle.groupCount), reason: '${item.topic}: sources');
      final overlap = {
        for (final group in item.puzzle.groups) ...group.alsoFits.map(GroupsPuzzle.normalise),
      };
      expect(overlap.length, lessThanOrEqualTo(1), reason: '${item.topic}: at most one shared tile');
      expect(item.puzzle.solve(limit: 2).length, 1, reason: '${item.topic}: one complete grouping');
      for (final tile in item.puzzle.tiles) {
        expect(tile.length, lessThanOrEqualTo(GroupsPuzzle.maxTileLength), reason: '${item.topic}: $tile');
      }
    }
  });

  test('most reserve puzzles have a tile that fits two groups', () {
    final withOverlap = generator.items.where((i) => i.puzzle.groups.any((g) => g.alsoFits.isNotEmpty)).length;
    expect(withOverlap * 2, greaterThan(generator.items.length), reason: 'the overlap is the point of the game');
  });

  test('no two reserve files share a subject or an answer', () {
    final topics = <String, String>{};
    final titles = <String, String>{};
    final answers = <String, String>{};
    for (var i = 0; i < generator.items.length; i++) {
      final item = generator.items[i];
      final file = generator.files[i];
      final topic = GroupsPuzzle.normalise(item.topic);
      expect(topics.containsKey(topic), isFalse, reason: '$file repeats the topic of ${topics[topic]}');
      topics[topic] = file;
      for (final group in item.puzzle.groups) {
        final title = GroupsPuzzle.normalise(group.title);
        expect(titles.containsKey(title), isFalse, reason: '$file repeats the group "${group.title}" of ${titles[title]}');
        titles[title] = file;
        final answer = (group.members.map(GroupsPuzzle.normalise).toList()..sort()).join('|');
        expect(answers.containsKey(answer), isFalse, reason: '$file repeats an answer of ${answers[answer]}');
        answers[answer] = file;
      }
    }
  });

  test('every tile is backed by a cited excerpt', () {
    for (final item in generator.items) {
      final excerpts = item.sources.map((s) => GroupsPuzzle.normalise(s.excerpt)).toList();
      for (final tile in item.puzzle.tiles) {
        expect(excerpts.any((e) => GroupsItem.names(tile, e)), isTrue,
            reason: '${item.topic}: $tile is named in no excerpt');
      }
      for (final source in item.sources) {
        expect(source.publisher, isNotEmpty);
        expect(source.url, startsWith('https://'));
      }
    }
  });

  test('generation is deterministic and valid over many dates', () {
    for (var day = 0; day < 14; day++) {
      final date = DateTime.utc(2026, 9, 10 + day);
      final a = generator.generate(date);
      final b = GroupsGenerator().generate(date);
      expect(a, b, reason: EditionClock.formatDate(date));
      expect(a.id.toString(), 'groups-${EditionClock.formatDate(date)}-en-v1');
      expect(a.game, GameKind.groups);
      expect(a.storyId, isNull);
      expect(a.locale, 'en-GB');
      expect(a.contentVersion, 1);
      expect(a.scoringVersion, 1);
      expect(a.sources, isNotEmpty);
      final puzzle = GroupsPuzzle.parse(a.payload, a.reveal);
      final item = generator.items[generator.pickFor(date)];
      expect(puzzle.tiles.toSet(), item.puzzle.tiles.toSet(), reason: 'the same twelve words');
      expect(puzzle.groups, item.puzzle.groups);
    }
  });

  test('the board is laid out for the date, not for the file', () {
    final item = generator.items.first;
    final layouts = {
      for (var day = 0; day < 10; day++)
        GroupsGenerator.layoutFor(DateTime.utc(2026, 3, 1 + day), item.puzzle).tiles.join('|'),
    };
    expect(layouts.length, greaterThan(1), reason: 'a reused puzzle does not look identical');
    expect(
      GroupsGenerator.layoutFor(DateTime.utc(2026, 3, 1), item.puzzle).tiles,
      GroupsGenerator.layoutFor(DateTime.utc(2026, 3, 1), item.puzzle).tiles,
    );
  });

  test('a reserve file is not reused within thirty days', () {
    final picks = <int>[];
    for (var day = 0; day < 150; day++) {
      picks.add(generator.pickFor(DateTime.utc(2026, 9, 1 + day)));
    }
    for (var i = 0; i < picks.length; i++) {
      for (var k = 1; k <= GroupsGenerator.reuseWindow && i - k >= 0; k++) {
        expect(picks[i], isNot(picks[i - k]), reason: 'day $i repeats day ${i - k}');
      }
    }
  });

  test('a news item from a template is wrapped like a reserve puzzle', () {
    final record = generator.fromTemplate(DateTime.utc(2026, 9, 10), skyItem(), storyId: 'nature-1-sky');
    expect(record.storyId, 'nature-1-sky');
    expect(record.id.toString(), 'groups-2026-09-10-en-v1');
    final puzzle = GroupsPuzzle.parse(record.payload, record.reveal);
    expect(puzzle.groups.first.title, 'Planets');
    expect(puzzle.tiles.toSet(), GroupsPuzzle.parse(skyPayload(), skyReveal()).tiles.toSet());
  });

  test('a template item missing its editor notes or a source is rejected', () {
    final noNotes = Map<String, dynamic>.from(skyItem())..remove('editorNotes');
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 10), noNotes), throwsFormatException);
    final noSources = Map<String, dynamic>.from(skyItem())..['sources'] = <Object?>[];
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 10), noSources), throwsFormatException);
    final thin = Map<String, dynamic>.from(skyItem())
      ..['sources'] = [
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Solar_System', 'excerpt': 'Venus, Mars, Jupiter and Saturn are planets.'},
      ];
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 10), thin), throwsFormatException,
        reason: 'the metals and the stars are then unsourced');
  });

  test('generating a date is quick', () {
    final clock = Stopwatch()..start();
    for (var day = 0; day < 30; day++) {
      GroupsGenerator().generate(DateTime.utc(2026, 9, 10 + day));
    }
    expect(clock.elapsedMilliseconds, lessThan(30 * 2000));
  });
}
