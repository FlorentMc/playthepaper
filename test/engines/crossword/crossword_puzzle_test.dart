import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

const openGrid = ['.....', '.....', '.....', '.....', '.....'];
const cornerGrid = ['#....', '.....', '.....', '.....', '....#'];
const staircaseGrid = ['##...', '#....', '.....', '....#', '...##'];

Map<String, dynamic> payloadFor(List<String> grid, {String clue = 'Clue'}) => {
      'size': 5,
      'grid': grid,
      'clues': {
        for (final d in Direction.values)
          d.name: [
            for (final e in deriveEntries(grid))
              if (e.direction == d) {...e.toJson(), 'clue': clue},
          ],
      },
    };

/// A hand-checked fill of [staircaseGrid].
const staircaseSolution = ['##FAN', '#TRUE', 'FRONT', 'REST#', 'YET##'];

void main() {
  group('deriveEntries', () {
    test('an open 5×5 numbers 1–5 across the top row and one across per row', () {
      final entries = deriveEntries(openGrid);
      expect(entries.length, 10);
      final across = entries.where((e) => e.direction == Direction.across).toList();
      final down = entries.where((e) => e.direction == Direction.down).toList();
      expect(across.map((e) => e.number), [1, 6, 7, 8, 9]);
      expect(down.map((e) => e.number), [1, 2, 3, 4, 5]);
      expect(across.every((e) => e.length == 5), isTrue);
      expect(down.every((e) => e.length == 5), isTrue);
      expect(across[1].cells, [5, 6, 7, 8, 9]);
      expect(down[2].cells, [2, 7, 12, 17, 22]);
    });

    test('corner blocks shorten the edge entries and shift the numbering', () {
      final entries = deriveEntries(cornerGrid);
      expect(entries.length, 10);
      final byLabel = {for (final e in entries) e.label: e};
      expect(byLabel['1 Across']!.cells, [1, 2, 3, 4]);
      expect(byLabel['1 Down']!.cells, [1, 6, 11, 16, 21]);
      expect(byLabel['4 Down']!.cells, [4, 9, 14, 19]);
      expect(byLabel['5 Across']!.cells, [5, 6, 7, 8, 9]);
      expect(byLabel['5 Down']!.cells, [5, 10, 15, 20]);
      expect(byLabel['8 Across']!.cells, [20, 21, 22, 23]);
      expect(byLabel.keys, isNot(contains('2 Across')));
    });

    test('the staircase pattern numbers as a printed mini would', () {
      final labels = deriveEntries(staircaseGrid).map((e) => '${e.label}:${e.length}').toList();
      expect(labels, [
        '1 Across:3',
        '1 Down:5',
        '2 Down:4',
        '3 Down:3',
        '4 Across:4',
        '4 Down:4',
        '5 Across:5',
        '5 Down:3',
        '6 Across:4',
        '7 Across:3',
      ]);
    });

    test('rejects a two-letter run', () {
      const grid = ['..#..', '.....', '.....', '.....', '..#..'];
      expect(() => deriveEntries(grid), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('2 letters'))));
    });

    test('rejects a letter cell that belongs to no entry', () {
      const grid = ['.#...', '#....', '.....', '....#', '...#.'];
      expect(() => deriveEntries(grid), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('no entry'))));
    });

    test('rejects a non-square grid and stray characters', () {
      expect(() => deriveEntries(['....', '.....', '.....', '.....', '.....']), throwsFormatException);
      expect(() => deriveEntries(['....x', '.....', '.....', '.....', '.....']), throwsFormatException);
    });
  });

  group('CrosswordPuzzle.parse', () {
    test('accepts a consistent payload and reveal and attaches clues', () {
      final puzzle = CrosswordPuzzle.parse(payloadFor(staircaseGrid), {'solution': staircaseSolution});
      expect(puzzle.size, 5);
      expect(puzzle.entries.length, 10);
      expect(puzzle.across.map((e) => e.number), [1, 4, 5, 6, 7]);
      expect(puzzle.down.map((e) => e.number), [1, 2, 3, 4, 5]);
      expect(puzzle.entries.every((e) => e.clue == 'Clue'), isTrue);
      expect(answersOf(puzzle), ['FAN', 'TRUE', 'FRONT', 'REST', 'YET', 'FROST', 'AUNT', 'NET', 'TREE', 'FRY']);
      expect(puzzle.numberAt(2), 1);
      expect(puzzle.numberAt(6), 4);
      expect(puzzle.numberAt(7), isNull);
      expect(puzzle.isBlock(0), isTrue);
      expect(puzzle.solutionAt(0), isNull);
      expect(puzzle.solutionAt(2), 'F');
      expect(puzzle.entryAt(12, Direction.across)!.label, '5 Across');
      expect(puzzle.entryAt(12, Direction.down)!.label, '1 Down');
      expect(puzzle.entryAt(2, Direction.down)!.label, '1 Down');
    });

    test('round-trips through toPayload and toReveal', () {
      final puzzle = CrosswordPuzzle.parse(payloadFor(cornerGrid), {'solution': ['#ABCD', 'EFGHI', 'JKLMN', 'OPQRS', 'TUVW#']});
      final again = CrosswordPuzzle.parse(puzzle.toPayload(), puzzle.toReveal());
      expect(again.entries, puzzle.entries);
      expect(again.solution, puzzle.solution);
    });

    test('exposes story seeding when present and round-trips it', () {
      final payload = payloadFor(staircaseGrid);
      (((payload['clues'] as Map)['across'] as List)[2] as Map)['storyId'] = 'front';
      payload['teaser'] = 'One of today\'s clues comes from the news.';
      final reveal = {
        'solution': staircaseSolution,
        'seeded': [
          {'label': '5 Across', 'storyId': 'front', 'excerpt': 'A cold front swept in.'},
        ],
      };
      final puzzle = CrosswordPuzzle.parse(payload, reveal);
      expect(puzzle.teaser, 'One of today\'s clues comes from the news.');
      final seeded = puzzle.entryLabelled('5 Across')!;
      expect(seeded.isSeeded, isTrue);
      expect(seeded.storyId, 'front');
      expect(puzzle.entries.where((e) => e.isSeeded), [seeded]);
      expect(puzzle.seeded, [const CrosswordSeedReveal(label: '5 Across', storyId: 'front', excerpt: 'A cold front swept in.')]);
      expect(puzzle.toPayload()['teaser'], payload['teaser']);
      expect(puzzle.toReveal()['seeded'], reveal['seeded']);
      final again = CrosswordPuzzle.parse(puzzle.toPayload(), puzzle.toReveal());
      expect(again.entries, puzzle.entries);
      expect(again.seeded, puzzle.seeded);
      expect(again.teaser, puzzle.teaser);
    });

    test('an unseeded puzzle has no teaser, no seeded entries and omits them from its json', () {
      final puzzle = CrosswordPuzzle.parse(payloadFor(staircaseGrid), {'solution': staircaseSolution});
      expect(puzzle.teaser, isNull);
      expect(puzzle.seeded, isEmpty);
      expect(puzzle.entries.any((e) => e.isSeeded), isFalse);
      expect(puzzle.toPayload().containsKey('teaser'), isFalse);
      expect(puzzle.toReveal().containsKey('seeded'), isFalse);
      expect(puzzle.entryLabelled('9 Down'), isNull);
    });

    test('rejects malformed seeding', () {
      final payload = payloadFor(staircaseGrid);
      final reveal = {'solution': staircaseSolution};
      expect(() => CrosswordPuzzle.parse({...payload, 'teaser': ' '}, reveal), throwsFormatException);
      expect(() => CrosswordPuzzle.parse({...payload, 'teaser': 3}, reveal), throwsFormatException);
      final badStory = payloadFor(staircaseGrid);
      (((badStory['clues'] as Map)['across'] as List)[0] as Map)['storyId'] = '';
      expect(() => CrosswordPuzzle.parse(badStory, reveal), throwsFormatException);
      for (final seeded in [
        'x',
        [1],
        [{'label': '5 Across', 'storyId': 'front'}],
        [{'label': '9 Across', 'storyId': 'front', 'excerpt': 'x'}],
        [{'label': '5 Across', 'storyId': '', 'excerpt': 'x'}],
        [
          {'label': '5 Across', 'storyId': 'a', 'excerpt': 'x'},
          {'label': '5 Across', 'storyId': 'b', 'excerpt': 'y'},
        ],
      ]) {
        expect(() => CrosswordPuzzle.parse(payload, {...reveal, 'seeded': seeded}), throwsFormatException, reason: '$seeded');
      }
    });

    test('rejects a clue whose number does not match the derived numbering', () {
      final payload = payloadFor(staircaseGrid);
      final across = (payload['clues'] as Map)['across'] as List;
      (across[1] as Map)['number'] = 5;
      expect(
        () => CrosswordPuzzle.parse(payload, {'solution': staircaseSolution}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('does not match'))),
      );
    });

    test('rejects a missing or extra clue', () {
      final payload = payloadFor(staircaseGrid);
      ((payload['clues'] as Map)['down'] as List).removeLast();
      expect(() => CrosswordPuzzle.parse(payload, {'solution': staircaseSolution}), throwsFormatException);
      final extra = payloadFor(staircaseGrid);
      ((extra['clues'] as Map)['across'] as List).add({'number': 9, 'row': 4, 'col': 0, 'length': 3, 'clue': 'x'});
      expect(() => CrosswordPuzzle.parse(extra, {'solution': staircaseSolution}), throwsFormatException);
    });

    test('rejects an empty clue', () {
      final payload = payloadFor(staircaseGrid);
      (((payload['clues'] as Map)['across'] as List)[0] as Map)['clue'] = '  ';
      expect(() => CrosswordPuzzle.parse(payload, {'solution': staircaseSolution}), throwsFormatException);
    });

    test('rejects a solution whose blocks or letters disagree with the grid', () {
      final payload = payloadFor(staircaseGrid);
      expect(
        () => CrosswordPuzzle.parse(payload, {'solution': ['##F.N', '#TRUE', 'FRONT', 'REST#', 'YET##']}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('must be a letter'))),
      );
      expect(
        () => CrosswordPuzzle.parse(payload, {'solution': ['##FAN', '#TRUE', 'FRONT', 'REST#', 'YETA#']}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('should be a block'))),
      );
      expect(() => CrosswordPuzzle.parse(payload, {'solution': ['##FAN', '#TRUE', 'FRONT', 'REST#']}), throwsFormatException);
      expect(() => CrosswordPuzzle.parse(payload, {'solution': ['##fan', '#TRUE', 'FRONT', 'REST#', 'YET##']}), throwsFormatException);
    });

    test('rejects a grid with a two-letter run even with matching clues', () {
      const grid = ['..#..', '.....', '.....', '.....', '..#..'];
      final payload = {'size': 5, 'grid': grid, 'clues': {'across': [], 'down': []}};
      expect(() => CrosswordPuzzle.parse(payload, {'solution': grid}), throwsFormatException);
    });

    test('rejects malformed shapes', () {
      expect(() => CrosswordPuzzle.parse({'size': '5', 'grid': openGrid, 'clues': {}}, {'solution': openGrid}), throwsFormatException);
      expect(() => CrosswordPuzzle.parse({'size': 5, 'grid': 'x', 'clues': {}}, {'solution': openGrid}), throwsFormatException);
      expect(() => CrosswordPuzzle.parse({'size': 4, 'grid': openGrid, 'clues': {}}, {'solution': openGrid}), throwsFormatException);
      expect(() => CrosswordPuzzle.parse(payloadFor(openGrid), {}), throwsFormatException);
    });
  });
}
