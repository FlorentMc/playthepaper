import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/chronology/chronology.dart';
import 'package:playthepaper/engines/chronology/chronology_generator.dart';

import 'fixtures.dart';

void main() {
  final generator = ChronologyGenerator();

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(ChronologyGenerator.fnv1a(''), 0x811C9DC5);
    expect(ChronologyGenerator.fnv1a('a'), 0xE40C292C);
    expect(ChronologyGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(ChronologyGenerator.seedFor(DateTime.utc(2026, 9, 10)), ChronologyGenerator.fnv1a('chronology-2026-09-10'));
  });

  test('every reserve file parses and there are at least thirty', () {
    expect(generator.problems, isEmpty);
    expect(generator.files.length, greaterThanOrEqualTo(ChronologyGenerator.minReserve));
    for (final file in generator.files) {
      expect(RegExp(r'^\d{3}\.json$').hasMatch(file), isTrue, reason: file);
    }
    for (final item in generator.items) {
      expect(item.sources.length, ChronologyPuzzle.eventCount, reason: '${item.topic}: one source per event');
      final explanation = item.reveal['explanation'] as String;
      expect(RegExp(r'[.!?](\s|$)').allMatches(explanation).length, 2, reason: '${item.topic}: two sentences');
      expect(item.editorNotes, isNotNull, reason: '${item.topic}: editor notes');
      for (final event in item.puzzle.events) {
        expect(event.text.length, lessThanOrEqualTo(90), reason: '${item.topic}: ${event.text}');
      }
    }
  });

  test('no two reserve files share a topic or an event', () {
    final topics = <String, String>{};
    final texts = <String, String>{};
    for (var i = 0; i < generator.items.length; i++) {
      final item = generator.items[i];
      final file = generator.files[i];
      final topic = item.topic.trim().toLowerCase();
      expect(topics.containsKey(topic), isFalse, reason: '$file repeats the topic of ${topics[topic]}');
      topics[topic] = file;
      for (final event in item.puzzle.events) {
        final text = event.text.trim().toLowerCase();
        expect(texts.containsKey(text), isFalse, reason: '$file repeats an event of ${texts[text]}');
        texts[text] = file;
      }
    }
  });

  test('generation is deterministic and valid over many dates', () {
    for (var day = 0; day < 12; day++) {
      final date = DateTime.utc(2026, 9, 10 + day);
      final a = generator.generate(date);
      final b = ChronologyGenerator().generate(date);
      expect(a, b, reason: EditionClock.formatDate(date));
      expect(a.id.toString(), 'chronology-${EditionClock.formatDate(date)}-en-v1');
      expect(a.game, GameKind.chronology);
      expect(a.storyId, isNull);
      expect(a.locale, 'en-GB');
      expect(a.sources, isNotEmpty);
      final puzzle = ChronologyPuzzle.parse(a.payload, a.reveal);
      expect(puzzle.events.length, 4);
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
    final record = generator.fromTemplate(DateTime.utc(2026, 9, 12), flightItem(), storyId: 'flight-1');
    expect(record.id.toString(), 'chronology-2026-09-12-en-v1');
    expect(record.storyId, 'flight-1');
    expect(record.sources.length, 4);
    expect(record.payload['title'], 'Milestones of flight');
    expect(ChronologyPuzzle.parse(record.payload, record.reveal).order, ['a', 'b', 'c', 'd']);

    final unsourced = flightItem();
    (unsourced['sources'] as List).removeAt(3);
    expect(
      () => generator.fromTemplate(DateTime.utc(2026, 9, 12), unsourced),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('1969'))),
    );
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), {'payload': {}}), throwsFormatException);
  });

  test('a broken reserve is reported and refuses to generate', () async {
    final dir = await Directory.systemTemp.createTemp('chronology_reserve');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/001.json').writeAsStringSync(jsonEncode(flightItem()));
    final broken = flightItem();
    (broken['reveal'] as Map)['order'] = ['a', 'b', 'd', 'c'];
    File('${dir.path}/002.json').writeAsStringSync(jsonEncode(broken));
    File('${dir.path}/003.json').writeAsStringSync('not json');
    final small = ChronologyGenerator(reserveDir: dir.path);
    expect(small.problems, hasLength(2));
    expect(small.problems.first, startsWith('002.json: '));
    expect(small.problems.last, startsWith('003.json: '));
    expect(small.files, ['001.json']);
    expect(() => small.generate(DateTime.utc(2026, 9, 10)), throwsStateError);

    File('${dir.path}/002.json').deleteSync();
    File('${dir.path}/003.json').deleteSync();
    final few = ChronologyGenerator(reserveDir: dir.path);
    expect(few.problems, isEmpty);
    expect(() => few.generate(DateTime.utc(2026, 9, 10)), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('at least 30'))));
    expect(ChronologyGenerator(reserveDir: '${dir.path}/missing').problems, hasLength(1));
  });
}
