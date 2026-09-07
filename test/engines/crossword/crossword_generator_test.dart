import 'dart:convert';
import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/edition_clock.dart';
import 'package:daypencil/engines/crossword/crossword_generator.dart';
import 'package:daypencil/engines/crossword/crossword_puzzle.dart';
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

  Map<String, dynamic> readPuzzle(String date) =>
      jsonDecode(File('content/puzzles/crossword-$date-en-v1.json').readAsStringSync()) as Map<String, dynamic>;

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

    test('unseeded output is identical to the published files', () {
      for (final date in ['2026-09-01', '2026-10-15', '2026-12-31']) {
        final d = EditionClock.parseDate(date);
        final result = generatorBefore(d).generate(d);
        expect(result, isNotNull, reason: date);
        expect(result!.seeds, isEmpty);
        expect(result.record.storyId, isNull);
        expect(jsonDecode(jsonEncode(result.record.toJson())), readPuzzle(date), reason: date);
      }
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

    test('drops seeds from the end when they cannot all be placed', () {
      final impossible = seed('XQZJV', story: 'odd', excerpt: 'XQZJV is not a word.');
      final date = DateTime.utc(2026, 11, 4);

      final partial = generatorBefore(date).generate(date, seeds: [seed('FJORD', story: 'norway', excerpt: 'A fjord.'), impossible], teaser: 't')!;
      expect(partial.seedsPlaced, 1);
      expect(partial.seeds.single.answer, 'FJORD');
      expect(partial.record.storyId, 'norway');
      expect(partial.record.payload['teaser'], 't');
      expect((partial.record.reveal['seeded'] as List).length, 1);

      final none = generatorBefore(date).generate(date, seeds: [impossible, seed('FJORD', excerpt: 'A fjord.')], teaser: 't')!;
      expect(none.seedsPlaced, 0);
      expect(none.record.storyId, isNull);
      expect(none.record.payload.containsKey('teaser'), isFalse);
      expect(none.record.reveal.containsKey('seeded'), isFalse);
      expect(jsonDecode(jsonEncode(none.record.toJson())), readPuzzle('2026-11-04'));
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
