import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> editionJson({List<String>? puzzles, List<Map<String, dynamic>>? stories}) => {
      'date': '2026-09-08',
      'kind': 'evergreen',
      'label': 'Evergreen · Science',
      'version': 1,
      'puzzles': puzzles ??
          [
            'word-2026-09-08-en-v1',
            'sudoku-2026-09-08-en-easy-v1',
            'sudoku-2026-09-08-en-medium-v1',
            'sudoku-2026-09-08-en-hard-v1',
            'letters-2026-09-08-en-v1',
            'crossword-2026-09-08-en-v1',
            'quiz-2026-09-08-en-v1',
          ],
      'stories': stories ??
          [
            for (final n in ['a', 'b', 'c'])
              {
                'id': 'story-$n',
                'headline': 'Headline $n',
                'summary': 'Summary.',
                'publisher': 'Wikipedia',
                'url': 'https://en.wikipedia.org/',
                'publishedAt': '2026-09-01',
              },
          ],
      'seeds': {'story-a': ['quiz:1', 'word'], 'story-b': ['quiz:2', 'crossword:5 Across']},
    };

void main() {
  group('EditionManifest', () {
    test('parses a complete edition and finds puzzles', () {
      final m = EditionManifest.fromJson(editionJson());
      expect(m.isComplete, isTrue);
      expect(m.puzzleFor(GameKind.sudoku, difficulty: Difficulty.hard)!.toString(), 'sudoku-2026-09-08-en-hard-v1');
      expect(m.puzzleFor(GameKind.sudoku), isNull);
      expect(m.story('story-c')!.headline, 'Headline c');
      expect(m.seeds['story-a'], ['quiz:1', 'word']);
      expect(EditionManifest.fromJson(m.toJson()), m);
    });

    test('is incomplete when a puzzle or story is missing', () {
      final noHard = EditionManifest.fromJson(editionJson(puzzles: [
        'word-2026-09-08-en-v1',
        'sudoku-2026-09-08-en-easy-v1',
        'sudoku-2026-09-08-en-medium-v1',
        'letters-2026-09-08-en-v1',
        'crossword-2026-09-08-en-v1',
        'quiz-2026-09-08-en-v1',
      ]));
      expect(noHard.isComplete, isFalse);
      final twoStories = EditionManifest.fromJson(editionJson(stories: [
        for (final n in ['a', 'b'])
          {
            'id': 'story-$n',
            'headline': 'h',
            'summary': 's',
            'publisher': 'p',
            'url': 'u',
            'publishedAt': 'd',
          }
      ]));
      expect(twoStories.isComplete, isFalse);
    });

    test('rejects a puzzle from another date', () {
      expect(
        () => EditionManifest.fromJson(editionJson(puzzles: ['word-2026-09-09-en-v1'])),
        throwsFormatException,
      );
    });

  });

  group('PuzzleRecord', () {
    final base = {
      'id': 'word-2026-09-08-en-v1',
      'game': 'word',
      'editionDate': '2026-09-08',
      'locale': 'en-GB',
      'contentVersion': 1,
      'scoringVersion': 1,
      'payload': {'length': 6, 'firstLetter': 'W', 'maxGuesses': 6},
      'reveal': {'answer': 'WHALES'},
      'storyId': 'story-a',
      'sources': [
        {'publisher': 'Wikipedia', 'url': 'https://example.org', 'excerpt': 'It is 330 m tall.'}
      ],
    };

    test('parses and round trips', () {
      final r = PuzzleRecord.fromJson(base);
      expect(r.game, GameKind.word);
      expect(r.storyId, 'story-a');
      expect(r.sources.single.excerpt, 'It is 330 m tall.');
      expect(PuzzleRecord.fromJson(r.toJson()), r);
    });

    test('rejects mismatched game or version', () {
      expect(() => PuzzleRecord.fromJson({...base, 'game': 'quiz'}), throwsFormatException);
      expect(() => PuzzleRecord.fromJson({...base, 'contentVersion': 2}), throwsFormatException);
    });

    test('missing fields fail loudly', () {
      final noPayload = Map<String, dynamic>.from(base)..remove('payload');
      expect(() => PuzzleRecord.fromJson(noPayload), throwsFormatException);
    });
  });
}
