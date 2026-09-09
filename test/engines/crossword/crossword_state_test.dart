import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:playthepaper/engines/crossword/crossword_state.dart';
import 'package:flutter_test/flutter_test.dart';

const grid = ['##...', '#....', '.....', '....#', '...##'];
const solution = ['##FAN', '#TRUE', 'FRONT', 'REST#', 'YET##'];

CrosswordPuzzle puzzle() => CrosswordPuzzle.parse(
      {
        'size': 5,
        'grid': grid,
        'clues': {
          for (final d in Direction.values)
            d.name: [
              for (final e in deriveEntries(grid))
                if (e.direction == d) {...e.toJson(), 'clue': 'Clue ${e.label}'},
            ],
        },
      },
      {'solution': solution},
    );

void main() {
  late CrosswordPuzzle p;
  setUp(() => p = puzzle());

  group('CrosswordState', () {
    test('starts at 1 Across with nothing filled', () {
      final s = CrosswordState.initial(p);
      expect(s.currentEntry.label, '1 Across');
      expect(s.selected, 2);
      expect(s.isFull, isFalse);
      expect(s.isSolved, isFalse);
      expect(s.hints, 0);
    });

    test('typing fills and advances along the entry, then to the next unfinished entry', () {
      var s = CrosswordState.initial(p).type('f').type('A');
      expect(s.letterAt(2), 'F');
      expect(s.letterAt(3), 'A');
      expect(s.selected, 4);
      s = s.type('N');
      expect(s.currentEntry.label, '4 Across', reason: 'entries run across first, then down');
      expect(s.selected, 6, reason: 'first empty cell of 4 Across');
    });

    test('non-letters are ignored', () {
      final s = CrosswordState.initial(p);
      expect(identical(s.type('1'), s), isTrue);
      expect(identical(s.type('ab'), s), isTrue);
    });

    test('backspace clears the current cell, then steps back and clears', () {
      var s = CrosswordState.initial(p).type('F').type('A');
      expect(s.selected, 4);
      s = s.backspace();
      expect(s.letterAt(3), isNull);
      expect(s.selected, 3);
      s = s.type('A').backspace();
      expect(s.letterAt(3), isNull);
      s = s.backspace();
      expect(s.letterAt(2), isNull);
      expect(s.selected, 2);
      expect(identical(s.backspace(), s), isTrue, reason: 'nothing before the first cell');
    });

    test('tapping selects and toggling swaps direction only where an entry exists', () {
      var s = CrosswordState.initial(p).select(12);
      expect(s.direction, Direction.across);
      s = s.toggleDirection();
      expect(s.direction, Direction.down);
      expect(s.currentEntry.label, '1 Down');
      expect(identical(s.select(0), s), isTrue, reason: 'blocks cannot be selected');
      expect(identical(s.select(99), s), isTrue);
    });

    test('arrows skip blocks and stop at the edge', () {
      var s = CrosswordState.initial(p).select(10);
      s = s.move(Arrow.up);
      expect(s.selected, 10, reason: 'nothing but blocks above (2,0)');
      s = s.select(4).move(Arrow.left);
      expect(s.selected, 3);
      s = s.select(6).move(Arrow.left);
      expect(s.selected, 6, reason: 'block then edge to the left');
      s = s.select(2).move(Arrow.down);
      expect(s.selected, 7);
      expect(s.direction, Direction.down);
    });

    test('next and previous clue wrap around', () {
      var s = CrosswordState.initial(p);
      final n = p.entries.length;
      for (var i = 0; i < n; i++) {
        s = s.nextClue();
      }
      expect(s.currentEntry.label, '1 Across');
      s = s.prevClue();
      expect(s.currentEntry, p.entries.last);
    });

    test('check marks wrong letters and counts a hint; retyping clears the mark', () {
      var s = CrosswordState.initial(p).type('X').type('A').type('N');
      s = s.select(2).checkWord();
      expect(s.isWrong(2), isTrue);
      expect(s.isWrong(3), isFalse);
      expect(s.hints, 1);
      s = s.select(2).type('F');
      expect(s.isWrong(2), isFalse);
      s = s.checkPuzzle();
      expect(s.wrong, isEmpty);
      expect(s.hints, 2);
    });

    test('reveal fills, locks, and counts a hint; locked cells are skipped and never erased', () {
      var s = CrosswordState.initial(p).select(2).revealWord();
      expect(s.letterAt(2), 'F');
      expect(s.letterAt(4), 'N');
      expect(s.isRevealed(3), isTrue);
      expect(s.hints, 1);
      s = s.select(2).type('Z');
      expect(s.letterAt(2), 'F', reason: 'locked cell keeps its letter');
      expect(s.selected, 3, reason: 'typing over a locked cell advances');
      s = s.select(3).backspace();
      expect(s.letterAt(3), 'A');
      s = s.revealPuzzle();
      expect(s.isSolved, isTrue);
      expect(s.hints, 2);
    });

    test('isSolved requires every cell to match', () {
      var s = CrosswordState.solved(p);
      expect(s.isSolved, isTrue);
      s = s.select(22).backspace().type('Q');
      expect(s.isFull, isTrue);
      expect(s.isSolved, isFalse);
    });

    test('json round trip keeps letters, marks, hints, time and selection', () {
      final s = CrosswordState.initial(p)
          .type('F')
          .type('A')
          .type('X')
          .select(2)
          .checkWord()
          .select(10)
          .revealCell()
          .tick()
          .tick()
          .select(12)
          .toggleDirection();
      final back = CrosswordState.fromJson(p, s.toJson());
      expect(back.letters, s.letters);
      expect(back.wrong, s.wrong);
      expect(back.revealed, s.revealed);
      expect(back.hints, 2);
      expect(back.elapsedSeconds, 2);
      expect(back.selected, 12);
      expect(back.direction, Direction.down);
    });

    test('progress that does not fit the puzzle is rejected', () {
      expect(() => CrosswordState.fromJson(p, {'letters': 'ABC'}), throwsFormatException);
      expect(() => CrosswordState.fromJson(p, {'letters': '##...#.............#...##', 'wrong': [0]}), throwsFormatException);
      expect(() => CrosswordState.fromJson(p, {'letters': '##...#.............#...##', 'hints': -1}), throwsFormatException);
      expect(() => CrosswordState.fromJson(p, {'letters': '##1..#.............#...##'}), throwsFormatException);
    });
  });
}
