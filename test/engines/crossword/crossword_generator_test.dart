import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/engines/crossword/crossword_generator.dart';
import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

CrosswordSeed seed(String answer, {String story = 'story-1', String? excerpt}) => CrosswordSeed(
      answer: answer,
      clue: 'Clue for $answer',
      storyId: story,
      excerpt: excerpt ?? 'The word ${answer.toLowerCase()} appears in this sentence.',
    );

void main() {
  final bank = CrosswordBank.fromJson(jsonDecode(File('content_src/crossword/clues.json').readAsStringSync()));
  final dictionary = File('tool/data/enable1.txt').readAsLinesSync().map((w) => w.trim().toUpperCase()).toSet();
  final bankAnswers = bank.entries.map((e) => e.answer).toSet();

  Map<String, dynamic> readFixture(String date) =>
      jsonDecode(File('test/fixtures/unseeded/crossword-$date-en-v1.json').readAsStringSync()) as Map<String, dynamic>;

  /// A generator that knows every published crossword before [date].
  CrosswordGenerator generatorBefore(DateTime date) {
    final generator = CrosswordGenerator(bank: bank, dictionary: dictionary);
    for (final f in Directory('content/puzzles').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('crossword-')) continue;
      final record = PuzzleRecord.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      if (!record.date.isBefore(date)) continue;
      generator.remember(record.date, answersOf(CrosswordPuzzle.parse(record.payload, record.reveal)).toSet());
    }
    return generator;
  }

  group('CrosswordSeed', () {
    test('accepts an uppercase 3–5 letter answer found as a word in its excerpt', () {
      final s = CrosswordSeed(answer: 'ANGEL', clue: 'Falls in Venezuela', storyId: 'falls', excerpt: "Angel Falls is the world's tallest.");
      expect(s.length, 5);
      expect(seed('WHALE', excerpt: "The whale's heart is huge.").answer, 'WHALE');
    });

    test('rejects a bad answer, an absent answer, an empty clue or an empty story', () {
      expect(() => seed('angel'), throwsFormatException);
      expect(() => seed('AB'), throwsFormatException);
      expect(() => seed('ANGELS'), throwsFormatException);
      expect(() => seed('ANGEL', excerpt: 'The angels sang.'), throwsFormatException);
      expect(() => seed('ANGEL', excerpt: 'Nothing here.'), throwsFormatException);
      expect(() => CrosswordSeed(answer: 'ANGEL', clue: ' ', storyId: 's', excerpt: 'angel'), throwsFormatException);
      expect(() => CrosswordSeed(answer: 'ANGEL', clue: 'x', storyId: '', excerpt: 'angel'), throwsFormatException);
    });
  });

  group('seedAssignments', () {
    const staircase = ['##...', '#....', '.....', '....#', '...##'];

    test('gives every seed a distinct entry of its length with agreeing crossings', () {
      final entries = deriveEntries(staircase);
      final all = seedAssignments(entries, [seed('FRONT'), seed('FROST')]);
      expect(all.length, 2);
      for (final a in all) {
        expect(a.values.toSet(), {'FRONT', 'FROST'});
        expect(a.keys.map((e) => e.length), everyElement(5));
      }
      expect(seedAssignments(entries, [seed('FRONT'), seed('BLAST')]), isEmpty);
      expect(seedAssignments(entries, const []), [const <CrosswordEntry, String>{}]);
    });
  });

  group('CrosswordGenerator', () {
    test('rejects a bank answer missing from the dictionary', () {
      final odd = CrosswordBank([...bank.entries, const BankEntry(answer: 'QZXJV', clues: ['x'])]);
      expect(() => CrosswordGenerator(bank: odd, dictionary: dictionary), throwsFormatException);
    });

    test('unseeded output is identical to the reference files', () {
      // The references were produced from the bank snapshot in the fixtures
      // directory by generating every date from 2026-09-01 in order, each
      // generation remembered for the next. They pin the unseeded path of
      // the generator: growing the live bank must not change this test.
      final snapshot = CrosswordBank.fromJson(jsonDecode(File('test/fixtures/unseeded/clues.json').readAsStringSync()));
      final generator = CrosswordGenerator(bank: snapshot, dictionary: dictionary);
      final references = {'2026-09-08', '2026-10-15', '2026-12-31'};
      var checked = 0;
      for (var d = DateTime.utc(2026, 9, 1); !d.isAfter(DateTime.utc(2026, 12, 31)); d = d.add(const Duration(days: 1))) {
        final result = generator.generate(d);
        final date = EditionClock.formatDate(d);
        expect(result, isNotNull, reason: date);
        expect(result!.seeds, isEmpty);
        expect(result.record.storyId, isNull);
        if (!references.contains(date)) continue;
        expect(jsonDecode(jsonEncode(result.record.toJson())), readFixture(date), reason: date);
        checked++;
      }
      expect(checked, references.length);
    });

    test('places every seed, clues them from the story and explains them in the reveal', () {
      final seeds = [
        seed('SHELL', story: 'beach', excerpt: 'A shell washed up on the beach.'),
        seed('WHEAT', story: 'harvest', excerpt: "This year's wheat harvest is early."),
        seed('OWL', story: 'night', excerpt: 'An owl hunts by night.'),
      ];
      final date = DateTime.utc(2026, 9, 1);
      final generator = CrosswordGenerator(bank: bank, dictionary: dictionary);
      final result = generator.generate(date, seeds: seeds, teaser: 'Three of today\'s clues come from the news.');
      expect(result, isNotNull);
      expect(result!.seedsPlaced, 3);
      expect(result.seeds.map((s) => s.answer), ['SHELL', 'WHEAT', 'OWL']);
      expect(result.answers, containsAll(['SHELL', 'WHEAT', 'OWL']));
      expect(result.answers.toSet().length, result.answers.length);
      expect(crosswordTemplates[result.templateIndex], result.record.payload['grid']);
      expect(result.templatesTried.last, result.templateIndex);

      final record = PuzzleRecord.fromJson(jsonDecode(jsonEncode(result.record.toJson())) as Map<String, dynamic>);
      expect(record.storyId, 'beach');
      expect(record.payload['teaser'], 'Three of today\'s clues come from the news.');
      final puzzle = CrosswordPuzzle.parse(record.payload, record.reveal);
      expect(puzzle.teaser, 'Three of today\'s clues come from the news.');
      final seededEntries = puzzle.entries.where((e) => e.isSeeded).toList();
      expect(seededEntries.length, 3);
      for (final e in seededEntries) {
        final s = seeds.firstWhere((s) => s.answer == puzzle.answerOf(e));
        expect(e.clue, s.clue);
        expect(e.storyId, s.storyId);
      }
      expect(puzzle.seeded.length, 3);
      for (final r in puzzle.seeded) {
        final entry = puzzle.entryLabelled(r.label)!;
        expect(entry.storyId, r.storyId);
        final s = seeds.firstWhere((s) => s.storyId == r.storyId);
        expect(r.excerpt, s.excerpt);
        expect(RegExp('\\b${puzzle.answerOf(entry)}\\b', caseSensitive: false).hasMatch(r.excerpt), isTrue);
      }
      for (final e in puzzle.entries.where((e) => !e.isSeeded)) {
        expect(bankAnswers, contains(puzzle.answerOf(e)));
      }
      expect(generator.history[date], result.answers.toSet());
    });

    test('a seed need not be in the bank', () {
      expect(bankAnswers.contains('FJORD'), isFalse);
      final date = DateTime.utc(2026, 11, 4);
      final result = generatorBefore(date).generate(date, seeds: [seed('FJORD', story: 'norway', excerpt: 'The fjord is deep.')])!;
      expect(result.seedsPlaced, 1);
      expect(result.answers, contains('FJORD'));
      final puzzle = CrosswordPuzzle.parse(result.record.payload, result.record.reveal);
      expect(puzzle.seeded.single.storyId, 'norway');
      expect(puzzle.answerOf(puzzle.entryLabelled(puzzle.seeded.single.label)!), 'FJORD');
    });

    test('is deterministic for the same date, seeds and history', () {
      final date = DateTime.utc(2026, 11, 3);
      final seeds = [seed('FJORD', excerpt: 'A fjord.'), seed('OAK', excerpt: 'An oak.')];
      final a = generatorBefore(date).generate(date, seeds: seeds)!;
      final b = generatorBefore(date).generate(date, seeds: seeds)!;
      expect(a.record, b.record);
    });

    test('keeps the largest subset of seeds that fits, whatever their order', () {
      final impossible = seed('XQZJV', story: 'odd', excerpt: 'XQZJV is not a word.');
      final hopeless = seed('QQQQ', story: 'odder', excerpt: 'QQQQ is not a word either.');
      final date = DateTime.utc(2026, 11, 4);

      final partial = generatorBefore(date).generate(date, seeds: [seed('FJORD', story: 'norway', excerpt: 'A fjord.'), impossible], teaser: 't')!;
      expect(partial.seedsPlaced, 1);
      expect(partial.seeds.single.answer, 'FJORD');
      expect(partial.record.storyId, 'norway');
      expect(partial.record.payload['teaser'], 't');
      expect((partial.record.reveal['seeded'] as List).length, 1);

      final later = generatorBefore(date).generate(date, seeds: [impossible, hopeless, seed('FJORD', story: 'norway', excerpt: 'A fjord.')], teaser: 't')!;
      expect(later.seedsPlaced, 1);
      expect(later.seeds.single.answer, 'FJORD');
      expect(later.record, partial.record);

      final none = generatorBefore(date).generate(date, seeds: [impossible, hopeless], teaser: 't')!;
      expect(none.seedsPlaced, 0);
      expect(none.record.storyId, isNull);
      expect(none.record.payload.containsKey('teaser'), isFalse);
      expect(none.record.reveal.containsKey('seeded'), isFalse);
      expect(none.record, generatorBefore(date).generate(date)!.record);
    });

    test('tries every subset of the seeds, largest first, in the seeds\' order', () {
      final a = seed('AAA', story: 'a', excerpt: 'aaa');
      final b = seed('BBB', story: 'b', excerpt: 'bbb');
      final c = seed('CCC', story: 'c', excerpt: 'ccc');
      List<String> names(List<CrosswordSeed> s) => s.map((x) => x.answer).toList();
      expect(seedSubsets([a, b, c]).map(names), [
        ['AAA', 'BBB', 'CCC'],
        ['AAA', 'BBB'],
        ['AAA', 'CCC'],
        ['BBB', 'CCC'],
        ['AAA'],
        ['BBB'],
        ['CCC'],
      ]);
      expect(seedSubsets([a, b, c, seed('DDD', story: 'd', excerpt: 'ddd')]).length, 15);
      expect(seedSubsets(const []), isEmpty);
    });

    test('falls back to the unseeded puzzle when the seed budget runs out', () {
      final date = DateTime.utc(2026, 11, 4);
      final seeds = [seed('FJORD', story: 'norway', excerpt: 'A fjord.'), seed('OAK', excerpt: 'An oak.')];
      final starved = CrosswordGenerator(bank: bank, dictionary: dictionary, seedNodes: 1).generate(date, seeds: seeds)!;
      expect(starved.seedsPlaced, 0);
      expect(starved.record, CrosswordGenerator(bank: bank, dictionary: dictionary).generate(date)!.record);
      final fed = CrosswordGenerator(bank: bank, dictionary: dictionary).generate(date, seeds: seeds)!;
      expect(fed.seedsPlaced, greaterThan(0));
    });

    test('rejects seeds that repeat an answer', () {
      final date = DateTime.utc(2026, 11, 5);
      expect(
        () => generatorBefore(date).generate(date, seeds: [seed('OAK', excerpt: 'oak'), seed('OAK', story: 'other', excerpt: 'oak')]),
        throwsFormatException,
      );
    });
  });
}
