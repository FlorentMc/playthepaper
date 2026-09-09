import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues_generator.dart';

import 'fixtures.dart';

void main() {
  final generator = FiveCluesGenerator();

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(FiveCluesGenerator.fnv1a(''), 0x811C9DC5);
    expect(FiveCluesGenerator.fnv1a('a'), 0xE40C292C);
    expect(FiveCluesGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(FiveCluesGenerator.seedFor(DateTime.utc(2026, 9, 10)), FiveCluesGenerator.fnv1a('fiveclues-2026-09-10'));
  });

  test('every reserve file parses and there are at least thirty', () {
    expect(generator.problems, isEmpty);
    expect(generator.files.length, greaterThanOrEqualTo(FiveCluesGenerator.minReserve));
    for (final file in generator.files) {
      expect(RegExp(r'^\d{3}\.json$').hasMatch(file), isTrue, reason: file);
    }
    for (final item in generator.items) {
      expect(item.sources, isNotEmpty, reason: '${item.topic}: sources');
      expect(item.editorNotes, isNotNull, reason: '${item.topic}: editor notes');
      expect(item.puzzle.explanations, hasLength(FiveCluesPuzzle.clueCount), reason: item.topic);
      for (final clue in item.puzzle.clues) {
        expect(clue.length, lessThanOrEqualTo(FiveCluesPuzzle.maxClueLength), reason: '${item.topic}: $clue');
      }
    }
  });

  test('no two reserve files share an answer, a topic or a clue', () {
    final answers = <String, String>{};
    final topics = <String, String>{};
    final clues = <String, String>{};
    for (var i = 0; i < generator.items.length; i++) {
      final item = generator.items[i];
      final file = generator.files[i];
      for (final form in [item.puzzle.answer, ...item.puzzle.aliases]) {
        final key = FiveCluesText.normalise(form);
        expect(answers.containsKey(key), isFalse, reason: '$file repeats the answer of ${answers[key]}');
        answers[key] = file;
      }
      final topic = item.topic.trim().toLowerCase();
      expect(topics.containsKey(topic), isFalse, reason: '$file repeats the topic of ${topics[topic]}');
      topics[topic] = file;
      for (final clue in item.puzzle.clues) {
        final key = FiveCluesText.normalise(clue);
        expect(clues.containsKey(key), isFalse, reason: '$file repeats a clue of ${clues[key]}');
        clues[key] = file;
      }
    }
  });

  test('generation is deterministic and valid over many dates', () {
    for (var day = 0; day < 12; day++) {
      final date = DateTime.utc(2026, 9, 10 + day);
      final a = generator.generate(date);
      final b = FiveCluesGenerator().generate(date);
      expect(a, b, reason: EditionClock.formatDate(date));
      expect(a.id.toString(), 'fiveclues-${EditionClock.formatDate(date)}-en-v1');
      expect(a.game, GameKind.fiveclues);
      expect(a.storyId, isNull);
      expect(a.locale, 'en-GB');
      expect(a.contentVersion, 1);
      expect(a.scoringVersion, 1);
      expect(a.sources, isNotEmpty);
      final puzzle = FiveCluesPuzzle.parse(a.payload, a.reveal);
      expect(puzzle.clues, hasLength(FiveCluesPuzzle.clueCount));
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
    final record = generator.fromTemplate(DateTime.utc(2026, 9, 12), honeyItem(), storyId: 'bees-1');
    expect(record.id.toString(), 'fiveclues-2026-09-12-en-v1');
    expect(record.storyId, 'bees-1');
    expect(record.sources, hasLength(1));
    expect(FiveCluesPuzzle.parse(record.payload, record.reveal).answer, 'Honey');

    final unsourced = honeyItem();
    (unsourced['sources'] as List)[0] = {
      'publisher': 'Wikipedia',
      'url': 'https://en.wikipedia.org/wiki/Nectar',
      'excerpt': 'Nectar is a sugar-rich liquid produced by plants.',
    };
    expect(
      () => generator.fromTemplate(DateTime.utc(2026, 9, 12), unsourced),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('appears in no source excerpt'))),
    );

    final untitled = honeyItem()..remove('topic');
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), untitled), throwsFormatException);
    expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), {'payload': <String, dynamic>{}}), throwsFormatException);
    expect(
      () => generator.fromTemplate(DateTime.utc(2026, 9, 12), honeyItem()..remove('sources')),
      throwsFormatException,
    );
  });

  test('a broken reserve is reported and refuses to generate', () async {
    final dir = await Directory.systemTemp.createTemp('fiveclues_reserve');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/001.json').writeAsStringSync(jsonEncode(honeyItem()));
    final broken = honeyItem();
    (broken['payload'] as Map)['clues'] = ['too few', 'clues here'];
    File('${dir.path}/002.json').writeAsStringSync(jsonEncode(broken));
    File('${dir.path}/003.json').writeAsStringSync('not json');
    final small = FiveCluesGenerator(reserveDir: dir.path);
    expect(small.problems, hasLength(2));
    expect(small.problems.first, startsWith('002.json: '));
    expect(small.problems.last, startsWith('003.json: '));
    expect(small.files, ['001.json']);
    expect(() => small.generate(DateTime.utc(2026, 9, 10)), throwsStateError);

    File('${dir.path}/002.json').deleteSync();
    File('${dir.path}/003.json').deleteSync();
    final few = FiveCluesGenerator(reserveDir: dir.path);
    expect(few.problems, isEmpty);
    expect(
      () => few.generate(DateTime.utc(2026, 9, 10)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('at least 30'))),
    );
    expect(FiveCluesGenerator(reserveDir: '${dir.path}/missing').problems, hasLength(1));
  });
}
