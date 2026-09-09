import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/uncover/uncover.dart';

import 'fixtures.dart';

void main() {
  final generator = UncoverGenerator();

  test('picks come from a stable FNV-1a hash of the puzzle name', () {
    expect(UncoverGenerator.fnv1a(''), 0x811C9DC5);
    expect(UncoverGenerator.fnv1a('a'), 0xE40C292C);
    expect(UncoverGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(UncoverGenerator.basePick(DateTime.utc(2026, 9, 10), 32), UncoverGenerator.fnv1a('uncover-2026-09-10') % 32);
  });

  test('every reserve file parses and reads as one written puzzle', () {
    expect(generator.checkReserve(), isEmpty);
    expect(generator.reserve.length, greaterThanOrEqualTo(30));
    for (final item in generator.reserve) {
      final where = '${item.file} (${item.subject})';
      expect(RegExp(r'^\d{3}\.json$').hasMatch(item.file), isTrue, reason: where);
      final puzzle = UncoverPuzzle.parse(item.payload, item.reveal);
      expect(puzzle.wordCount, inInclusiveRange(90, 140), reason: where);
      expect(puzzle.hints, hasLength(3), reason: where);
      expect(puzzle.hiddenCount, greaterThanOrEqualTo(UncoverPuzzle.minHiddenWords), reason: where);
      expect(puzzle.subjectCount, greaterThanOrEqualTo(1), reason: where);
      expect(item.editorNotes, isNotNull, reason: where);
      expect(item.sources, isNotEmpty, reason: where);
      for (final source in item.sources) {
        expect(source.url, startsWith('https://'), reason: where);
        expect(source.excerpt.length, greaterThan(20), reason: where);
      }
      final left = UncoverText.tokenise(puzzle.maskedText).where((t) => t.isWord).map((t) => t.normalised);
      for (final word in puzzle.answerWords) {
        expect(left, isNot(contains(word)), reason: '$where leaks $word');
      }
    }
  });

  test('no two reserve files share a subject, an alias or a topic', () {
    final answers = <String, String>{};
    final topics = <String, String>{};
    for (final item in generator.reserve) {
      final puzzle = UncoverPuzzle.parse(item.payload, item.reveal);
      for (final answer in puzzle.acceptedAnswers) {
        expect(answers.containsKey(answer), isFalse, reason: '${item.file} repeats the answer of ${answers[answer]}');
        answers[answer] = item.file;
      }
      final topic = item.topic.trim().toLowerCase();
      expect(topics.containsKey(topic), isFalse, reason: '${item.file} repeats the topic of ${topics[topic]}');
      topics[topic] = item.file;
    }
  });

  test('generation is deterministic and valid over many dates', () {
    for (var day = 0; day < 14; day++) {
      final date = DateTime.utc(2026, 9, 10 + day);
      final record = generator.generate(date);
      expect(record, UncoverGenerator().generate(date), reason: EditionClock.formatDate(date));
      expect(record.id.toString(), 'uncover-${EditionClock.formatDate(date)}-en-v1');
      expect(record.game, GameKind.uncover);
      expect(record.locale, 'en-GB');
      expect(record.contentVersion, 1);
      expect(record.scoringVersion, 1);
      expect(record.storyId, isNull);
      expect(record.sources, isNotEmpty);
      final puzzle = UncoverPuzzle.parse(record.payload, record.reveal);
      expect(puzzle.subject, generator.itemFor(date).subject);
    }
  });

  test('a reserve file does not come round again for thirty days', () {
    final count = generator.reserve.length;
    final picks = [for (var day = 0; day < 120; day++) UncoverGenerator.pickFor(DateTime.utc(2026, 9, 1 + day), count)];
    for (var i = 0; i < picks.length; i++) {
      for (var k = 1; k <= UncoverGenerator.avoidWindow && i - k >= 0; k++) {
        expect(picks[i], isNot(picks[i - k]), reason: 'day $i repeats day ${i - k}');
      }
    }
    expect(picks.toSet().length, count, reason: 'every file is used');
    expect(UncoverGenerator.pickFor(DateTime.utc(2026, 9, 10), 1), 0);
    expect(() => UncoverGenerator.pickFor(DateTime.utc(2026, 9, 10), 0), throwsArgumentError);
  });

  group('fromTemplate', () {
    test('wraps a news item with its story', () {
      final record = generator.fromTemplate(DateTime.utc(2026, 9, 12), boatItem(), storyId: 'boats-1');
      expect(record.id.toString(), 'uncover-2026-09-12-en-v1');
      expect(record.storyId, 'boats-1');
      expect(record.sources, hasLength(1));
      expect(UncoverPuzzle.parse(record.payload, record.reveal).subject, 'Paper Boat');
    });

    test('masks the text itself when the payload leaves it out', () {
      final item = boatItem();
      (item['payload'] as Map).remove('text');
      final record = generator.fromTemplate(DateTime.utc(2026, 9, 12), item);
      expect(record.payload['text'], boatMaskedText);
      expect(record.storyId, isNull);
    });

    test('refuses a malformed item', () {
      expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), const {}), throwsFormatException);
      expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), {'payload': boatPayload()}), throwsFormatException);
      final broken = boatItem();
      (broken['reveal'] as Map)['subject'] = 'Cardboard Canoe';
      expect(() => generator.fromTemplate(DateTime.utc(2026, 9, 12), broken), throwsFormatException);
    });
  });

  test('a broken reserve is reported file by file', () async {
    final dir = await Directory.systemTemp.createTemp('uncover_reserve');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/001.json').writeAsStringSync(jsonEncode(boatItem()));
    final broken = boatItem();
    (broken['payload'] as Map)['text'] = boatText;
    File('${dir.path}/002.json').writeAsStringSync(jsonEncode(broken));
    File('${dir.path}/003.json').writeAsStringSync('not json');
    final sourceless = boatItem()..remove('sources');
    File('${dir.path}/004.json').writeAsStringSync(jsonEncode(sourceless));

    final small = UncoverGenerator(reserveDir: dir.path);
    final problems = small.checkReserve();
    expect(problems, hasLength(3));
    expect(problems.keys.map((p) => p.split(Platform.pathSeparator).last), ['002.json', '003.json', '004.json']);
    expect(() => small.reserve, throwsFormatException);

    for (final name in ['002.json', '003.json', '004.json']) {
      File('${dir.path}/$name').deleteSync();
    }
    final one = UncoverGenerator(reserveDir: dir.path);
    expect(one.checkReserve(), isEmpty);
    expect(one.generate(DateTime.utc(2026, 9, 10)).payload['text'], boatMaskedText);
    expect(UncoverGenerator(reserveDir: '${dir.path}/missing').checkReserve, throwsFormatException);
  });
}
