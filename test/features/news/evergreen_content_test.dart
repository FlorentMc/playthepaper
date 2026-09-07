import 'dart:convert';
import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/engines/correct/correct_engine.dart';
import 'package:daypencil/engines/number/number_engine.dart';
import 'package:daypencil/engines/where/where_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Directory('content_src/evergreen');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final date = DateTime.utc(2026, 1, 1);

  test('there are seven evergreen editions', () {
    expect(files.length, 7);
  });

  for (final file in files) {
    final slug = file.uri.pathSegments.last.replaceAll('.json', '');
    group(slug, () {
      late Map<String, dynamic> json;
      late List<Story> stories;
      late Map<String, PuzzleRecord> records;

      setUpAll(() {
        json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        stories = (json['stories'] as List).map((s) => Story.fromJson(s as Map<String, dynamic>)).toList();
        final puzzles = json['puzzles'] as Map<String, dynamic>;
        records = {
          for (final entry in puzzles.entries)
            entry.key: PuzzleRecord.fromJson({
              'id': PuzzleId(game: GameKind.fromSlug(entry.key), date: date).toString(),
              'game': entry.key,
              'editionDate': '2026-01-01',
              'locale': 'en-GB',
              'contentVersion': 1,
              'scoringVersion': 1,
              'payload': (entry.value as Map)['payload'],
              'reveal': (entry.value as Map)['reveal'],
              'storyId': stories.firstWhere((s) => s.game.slug == entry.key).id,
              'sources': (entry.value as Map)['sources'],
            }),
        };
      });

      test('has a slug, a label and one story per news game', () {
        expect(json['slug'], slug);
        expect((json['label'] as String).startsWith('Evergreen · '), isTrue);
        expect(stories.map((s) => s.game).toSet(), GameKind.newsOrder.toSet());
        for (final s in stories) {
          expect(s.id, '$slug-${s.game.slug}');
          expect(s.publisher, 'Wikipedia');
          expect(s.url, startsWith('https://en.wikipedia.org/wiki/'));
          expect(s.publishedAt, 'evergreen');
          expect(s.summary.trim().split(RegExp(r'(?<=[.!?])\s+')).length, inInclusiveRange(2, 3));
        }
      });

      test('every puzzle has verified sources and matches its story', () {
        expect(records.keys.toSet(), GameKind.newsOrder.map((g) => g.slug).toSet());
        for (final r in records.values) {
          expect(r.sources, isNotEmpty, reason: '${r.id} needs a source');
          final story = stories.firstWhere((s) => s.id == r.storyId);
          expect(r.sources.map((s) => s.url), contains(story.url));
          for (final s in r.sources) {
            expect(s.excerpt.length, greaterThan(40));
          }
        }
      });

      test('correct parses and is winnable', () {
        final r = records['correct']!;
        final puzzle = CorrectPuzzle.parse(r.payload);
        final reveal = CorrectReveal.parse(r.reveal, puzzle);
        expect(puzzle.evidence.length, 2);
        expect(puzzle.maxAttempts, 3);
        final sentences = puzzle.dispatch.trim().split(RegExp(r'(?<=[.!?])\s+'));
        expect(sentences.length, inInclusiveRange(2, 3));
        final won = CorrectState(puzzle: puzzle, reveal: reveal).pickDetail(reveal.alteredDetail).pickOption(reveal.correctOption);
        expect(won.status, CorrectStatus.won);
        expect(reveal.correctedDispatch(puzzle), isNot(puzzle.dispatch));
        expect(puzzle.options, contains(puzzle.details[reveal.alteredDetail]),
            reason: 'the altered text is offered as a distractor');
      });

      test('number parses and the answer sits inside the slider', () {
        final r = records['number']!;
        final puzzle = NumberPuzzle.parse(r.payload);
        final reveal = NumberReveal.parse(r.reveal, puzzle);
        expect(reveal.answer, greaterThan(puzzle.min));
        expect(reveal.answer, lessThan(puzzle.max));
        expect(reveal.solved(reveal.answer), isTrue);
        expect(reveal.score(reveal.answer), 100);
        expect(puzzle.snap(reveal.answer), closeTo(reveal.answer, puzzle.step / 2));
      });

      test('where parses with a sensible radius', () {
        final r = records['where']!;
        final puzzle = WherePuzzle.parse(r.payload);
        final reveal = WhereReveal.parse(r.reveal);
        expect(puzzle.clues.length, 2);
        expect(reveal.acceptRadiusKm, inInclusiveRange(100, 1000));
        expect(reveal.solved(0), isTrue);
        expect(reveal.solved(reveal.acceptRadiusKm + 1), isFalse);
        for (final clue in puzzle.clues) {
          expect(clue.toLowerCase(), isNot(contains(reveal.placeName.split(',').first.toLowerCase())),
              reason: 'clues must not name the place');
        }
      });
    });
  }
}
