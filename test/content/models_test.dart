import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';
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
            'correct-2026-09-08-en-v1',
            'number-2026-09-08-en-v1',
            'where-2026-09-08-en-v1',
          ],
      'stories': stories ??
          [
            for (final g in ['correct', 'number', 'where'])
              {
                'id': 'story-$g',
                'game': g,
                'headline': 'Headline $g',
                'summary': 'Summary.',
                'publisher': 'Wikipedia',
                'url': 'https://en.wikipedia.org/',
                'publishedAt': '2026-09-01',
              },
          ],
    };

void main() {
  group('EditionManifest', () {
    test('parses a complete edition and finds puzzles', () {
      final m = EditionManifest.fromJson(editionJson());
      expect(m.isComplete, isTrue);
      expect(m.puzzleFor(GameKind.sudoku, difficulty: Difficulty.hard)!.toString(), 'sudoku-2026-09-08-en-hard-v1');
      expect(m.puzzleFor(GameKind.sudoku), isNull);
      expect(m.storyFor(GameKind.where)!.headline, 'Headline where');
      expect(EditionManifest.fromJson(m.toJson()), m);
    });

    test('is incomplete when a puzzle or story is missing', () {
      final noHard = EditionManifest.fromJson(editionJson(puzzles: [
        'word-2026-09-08-en-v1',
        'sudoku-2026-09-08-en-easy-v1',
        'sudoku-2026-09-08-en-medium-v1',
        'letters-2026-09-08-en-v1',
        'crossword-2026-09-08-en-v1',
        'correct-2026-09-08-en-v1',
        'number-2026-09-08-en-v1',
        'where-2026-09-08-en-v1',
      ]));
      expect(noHard.isComplete, isFalse);
      final noStory = EditionManifest.fromJson(editionJson(stories: []));
      expect(noStory.isComplete, isFalse);
    });

    test('rejects a puzzle from another date', () {
      expect(
        () => EditionManifest.fromJson(editionJson(puzzles: ['word-2026-09-09-en-v1'])),
        throwsFormatException,
      );
    });

    test('rejects a story for a classic game', () {
      expect(
        () => EditionManifest.fromJson(editionJson(stories: [
          {
            'id': 's',
            'game': 'word',
            'headline': 'h',
            'summary': 's',
            'publisher': 'p',
            'url': 'u',
            'publishedAt': 'd',
          }
        ])),
        throwsFormatException,
      );
    });
  });

  group('PuzzleRecord', () {
    final base = {
      'id': 'number-2026-09-08-en-v1',
      'game': 'number',
      'editionDate': '2026-09-08',
      'locale': 'en-GB',
      'contentVersion': 1,
      'scoringVersion': 1,
      'payload': {'question': 'How tall?'},
      'reveal': {'answer': 330},
      'storyId': 'story-number',
      'sources': [
        {'publisher': 'Wikipedia', 'url': 'https://example.org', 'excerpt': 'It is 330 m tall.'}
      ],
    };

    test('parses and round trips', () {
      final r = PuzzleRecord.fromJson(base);
      expect(r.game, GameKind.number);
      expect(r.sources.single.excerpt, 'It is 330 m tall.');
      expect(PuzzleRecord.fromJson(r.toJson()), r);
    });

    test('rejects mismatched game or version', () {
      expect(() => PuzzleRecord.fromJson({...base, 'game': 'where'}), throwsFormatException);
      expect(() => PuzzleRecord.fromJson({...base, 'contentVersion': 2}), throwsFormatException);
    });

    test('news puzzles must reference a story', () {
      final noStory = Map<String, dynamic>.from(base)..remove('storyId');
      expect(() => PuzzleRecord.fromJson(noStory), throwsFormatException);
    });

    test('missing fields fail loudly', () {
      final noPayload = Map<String, dynamic>.from(base)..remove('payload');
      expect(() => PuzzleRecord.fromJson(noPayload), throwsFormatException);
    });
  });
}
