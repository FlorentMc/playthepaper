import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/linked/linked.dart';
import 'package:playthepaper/engines/linked/linked_generator.dart';

import 'fixtures.dart';

void main() {
  final generator = LinkedGenerator();

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(LinkedGenerator.fnv1a(''), 0x811C9DC5);
    expect(LinkedGenerator.fnv1a('a'), 0xE40C292C);
    expect(LinkedGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(LinkedGenerator.seedFor(DateTime.utc(2026, 9, 10)), LinkedGenerator.fnv1a('linked-2026-09-10'));
  });

  test('every reserve file parses and there are at least thirty', () {
    expect(generator.problems, isEmpty);
    expect(generator.files.length, greaterThanOrEqualTo(LinkedGenerator.minReserve));
    for (final file in generator.files) {
      expect(RegExp(r'^\d{3}\.json$').hasMatch(file), isTrue, reason: file);
    }
    for (final item in generator.items) {
      expect(item.sources, isNotEmpty, reason: '${item.topic}: sources');
      expect(item.editorNotes, isNotNull, reason: '${item.topic}: editor notes');
      expect(item.puzzle.explanations, hasLength(LinkedPuzzle.setCount + 1), reason: item.topic);
      for (final set in item.puzzle.sets) {
        expect(set.clues, hasLength(LinkedPuzzle.cluesPerSet), reason: item.topic);
        expect(set.hint.length, lessThanOrEqualTo(LinkedPuzzle.maxClueLength), reason: item.topic);
      }
    }
  });

  test('no two reserve files share a final subject, a topic or a clue', () {
    final finals = <String, String>{};
    final topics = <String, String>{};
    final clues = <String, String>{};
    for (var i = 0; i < generator.items.length; i++) {
      final item = generator.items[i];
      final file = generator.files[i];
      for (final form in [item.puzzle.finalAnswer, ...item.puzzle.finalAliases]) {
        final key = LinkedText.normalise(form);
        expect(finals.containsKey(key), isFalse, reason: '$file repeats the final subject of ${finals[key]}');
        finals[key] = file;
      }
      final topic = item.topic.trim().toLowerCase();
      expect(topics.containsKey(topic), isFalse, reason: '$file repeats the topic of ${topics[topic]}');
      topics[topic] = file;
      for (final set in item.puzzle.sets) {
        for (final clue in set.clues) {
          final key = LinkedText.normalise(clue);
          expect(clues.containsKey(key), isFalse, reason: '$file repeats a clue of ${clues[key]}');
          clues[key] = file;
        }
      }
    }
  });

  test('generation is deterministic and valid over many dates', () {
    for (var day = 0; day < 12; day++) {
      final date = DateTime.utc(2026, 9, 10 + day);
      final a = generator.generate(date);
      final b = LinkedGenerator().generate(date);
      expect(a, b, reason: EditionClock.formatDate(date));
      expect(a.id.toString(), 'linked-${EditionClock.formatDate(date)}-en-v1');
      expect(a.game, GameKind.linked);
      expect(a.storyId, isNull);
      expect(a.locale, 'en-GB');
      expect(a.contentVersion, 1);
      expect(a.scoringVersion, 1);
      expect(a.sources, isNotEmpty);
      final puzzle = LinkedPuzzle.parse(a.payload, a.reveal);
      expect(puzzle.sets, hasLength(LinkedPuzzle.setCount));
    }
  });

  test('a reserve file does not come round again within thirty days', () {
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
    final record = generator.fromTemplate(DateTime.utc(2026, 9, 12), flagItem(), storyId: 'ireland-1');
    expect(record.id.toString(), 'linked-2026-09-12-en-v1');
    expect(record.storyId, 'ireland-1');
    expect(record.sources, hasLength(1));
    expect(LinkedPuzzle.parse(record.payload, record.reveal).finalAnswer, 'The flag of Ireland');

    final unnamed = flagItem();
    (unnamed['sources'] as List)[0] = {
      'publisher': 'Wikipedia',
      'url': 'https://en.wikipedia.org/wiki/Flag_of_Ireland',
      'excerpt': 'The proportions of the flag of Ireland are 1:2.',
    };
    expect(
      () => generator.fromTemplate(DateTime.utc(2026, 9, 12), unnamed),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('appears in no source excerpt'))),
    );

    final untouched = flagItem();
    (untouched['reveal'] as Map)['final'] = 'A vexillological curiosity';
    expect(
      () => generator.fromTemplate(DateTime.utc(2026, 9, 12), untouched),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('touched by no source excerpt'))),
    );

    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), flagItem()..remove('topic')), throwsFormatException);
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), flagItem()..remove('sources')), throwsFormatException);
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), {'payload': <String, dynamic>{}}), throwsFormatException);
  });

  test('a broken reserve is reported and refuses to generate', () async {
    final dir = await Directory.systemTemp.createTemp('linked_reserve');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/001.json').writeAsStringSync(jsonEncode(flagItem()));
    final broken = flagItem();
    (broken['reveal'] as Map)['answers'] = ['Green', 'White'];
    File('${dir.path}/002.json').writeAsStringSync(jsonEncode(broken));
    File('${dir.path}/003.json').writeAsStringSync('not json');
    final small = LinkedGenerator(reserveDir: dir.path);
    expect(small.problems, hasLength(2));
    expect(small.problems.first, startsWith('002.json: '));
    expect(small.problems.last, startsWith('003.json: '));
    expect(small.files, ['001.json']);
    expect(() => small.generate(DateTime.utc(2026, 9, 10)), throwsStateError);

    File('${dir.path}/002.json').deleteSync();
    File('${dir.path}/003.json').deleteSync();
    final few = LinkedGenerator(reserveDir: dir.path);
    expect(few.problems, isEmpty);
    expect(
      () => few.generate(DateTime.utc(2026, 9, 10)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('at least 30'))),
    );
    expect(LinkedGenerator(reserveDir: '${dir.path}/missing').problems, hasLength(1));
  });
}
