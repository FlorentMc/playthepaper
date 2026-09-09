import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/crossmatch/crossmatch.dart';
import 'package:playthepaper/engines/crossmatch/crossmatch_generator.dart';

import 'fixtures.dart';

void main() {
  final generator = CrossmatchGenerator();

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(CrossmatchGenerator.fnv1a(''), 0x811C9DC5);
    expect(CrossmatchGenerator.fnv1a('a'), 0xE40C292C);
    expect(CrossmatchGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(CrossmatchGenerator.seedFor(DateTime.utc(2026, 9, 10)), CrossmatchGenerator.fnv1a('crossmatch-2026-09-10'));
  });

  test('every reserve file parses and there are at least thirty', () {
    expect(generator.problems, isEmpty);
    expect(generator.files.length, greaterThanOrEqualTo(CrossmatchGenerator.minReserve));
    for (final file in generator.files) {
      expect(RegExp(r'^\d{3}\.json$').hasMatch(file), isTrue, reason: file);
    }
    for (final item in generator.items) {
      expect(item.sources, isNotEmpty, reason: item.topic);
      expect(item.editorNotes, isNotNull, reason: '${item.topic}: editor notes');
      for (final criterion in [...item.puzzle.rows, ...item.puzzle.cols]) {
        expect(criterion.length, lessThanOrEqualTo(24), reason: '${item.topic}: $criterion');
      }
      for (var t = 0; t < CrossmatchPuzzle.cellCount; t++) {
        expect(item.puzzle.tiles[t].length, lessThanOrEqualTo(22), reason: '${item.topic}: ${item.puzzle.tiles[t]}');
        expect(item.puzzle.explanations[t].trim(), isNotEmpty, reason: '${item.topic}: ${item.puzzle.tiles[t]}');
      }
    }
  });

  test('no two reserve files share a topic or a tile', () {
    final topics = <String, String>{};
    final tiles = <String, String>{};
    for (var i = 0; i < generator.items.length; i++) {
      final item = generator.items[i];
      final file = generator.files[i];
      final topic = CrossmatchPuzzle.normalise(item.topic);
      expect(topics.containsKey(topic), isFalse, reason: '$file repeats the topic of ${topics[topic]}');
      topics[topic] = file;
      for (final tile in item.puzzle.tiles) {
        final key = CrossmatchPuzzle.normalise(tile);
        expect(tiles.containsKey(key), isFalse, reason: '$file repeats the tile "$tile" of ${tiles[key]}');
        tiles[key] = file;
      }
    }
  });

  test('every reserve grid has exactly one placement', () {
    for (var i = 0; i < generator.items.length; i++) {
      final puzzle = generator.items[i].puzzle;
      final fits = [for (final cells in puzzle.fits) cells];
      expect(CrossmatchSolver.countMatchings(fits), 1, reason: generator.files[i]);
      final assignment = CrossmatchSolver.solve(fits)!;
      for (var t = 0; t < CrossmatchPuzzle.cellCount; t++) {
        expect(assignment[t], puzzle.cellOf(t), reason: '${generator.files[i]}: ${puzzle.tiles[t]}');
      }
    }
  });

  test('generation is deterministic and valid over many dates', () {
    for (var day = 0; day < 12; day++) {
      final date = DateTime.utc(2026, 9, 10 + day);
      final a = generator.generate(date);
      final b = CrossmatchGenerator().generate(date);
      expect(a, b, reason: EditionClock.formatDate(date));
      expect(a.id.toString(), 'crossmatch-${EditionClock.formatDate(date)}-en-v1');
      expect(a.game, GameKind.crossmatch);
      expect(a.storyId, isNull);
      expect(a.locale, 'en-GB');
      expect(a.sources, isNotEmpty);
      expect(CrossmatchPuzzle.parse(a.payload, a.reveal).tiles.length, CrossmatchPuzzle.cellCount);
    }
  });

  test('a reserve file does not come round again for thirty days', () {
    final picks = <int>[];
    for (var day = 0; day < 120; day++) {
      picks.add(generator.pickFor(DateTime.utc(2026, 9, 1 + day)));
    }
    for (var i = 0; i < picks.length; i++) {
      for (var k = 1; k <= generator.reuseSpan && i - k >= 0; k++) {
        expect(picks[i], isNot(picks[i - k]), reason: 'day $i repeats day ${i - k}');
      }
    }
    expect(picks.toSet().length, generator.files.length);
  });

  test('fromTemplate wraps a news item with its story and validates it', () {
    final record = generator.fromTemplate(DateTime.utc(2026, 9, 12), placesItem(), storyId: 'places-1');
    expect(record.id.toString(), 'crossmatch-2026-09-12-en-v1');
    expect(record.storyId, 'places-1');
    expect(record.sources.length, 9);
    expect(record.payload['title'], 'Islands and volcanoes');
    expect(CrossmatchPuzzle.parse(record.payload, record.reveal).rows.first, 'City');

    final unsourced = placesItem();
    (unsourced['sources'] as List).removeAt(7);
    expect(
      () => generator.fromTemplate(DateTime.utc(2026, 9, 12), unsourced),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Hekla'))),
    );
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), {'payload': {}}), throwsFormatException);
  });

  test('a broken reserve is reported and refuses to generate', () async {
    final dir = await Directory.systemTemp.createTemp('crossmatch_reserve');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/001.json').writeAsStringSync(jsonEncode(placesItem()));
    final broken = placesItem();
    ((broken['reveal'] as Map)['fits'] as Map)['Hekla'] = [
      [2, 1],
      [1, 1],
    ];
    File('${dir.path}/002.json').writeAsStringSync(jsonEncode(broken));
    File('${dir.path}/003.json').writeAsStringSync('not json');
    final small = CrossmatchGenerator(reserveDir: dir.path);
    expect(small.problems, hasLength(2));
    expect(small.problems.first, startsWith('002.json: '));
    expect(small.problems.last, startsWith('003.json: '));
    expect(small.files, ['001.json']);
    expect(() => small.generate(DateTime.utc(2026, 9, 10)), throwsStateError);

    File('${dir.path}/002.json').deleteSync();
    File('${dir.path}/003.json').deleteSync();
    final few = CrossmatchGenerator(reserveDir: dir.path);
    expect(few.problems, isEmpty);
    expect(
      () => few.generate(DateTime.utc(2026, 9, 10)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('at least 30'))),
    );
    expect(CrossmatchGenerator(reserveDir: '${dir.path}/missing').problems, hasLength(1));
  });
}
