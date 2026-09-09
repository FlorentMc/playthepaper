import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PuzzleId', () {
    test('parses and formats a classic id', () {
      final id = PuzzleId.parse('word-2026-09-08-en-v1');
      expect(id.game, GameKind.word);
      expect(id.date, DateTime.utc(2026, 9, 8));
      expect(id.language, 'en');
      expect(id.difficulty, isNull);
      expect(id.version, 1);
      expect(id.toString(), 'word-2026-09-08-en-v1');
    });

    test('parses a sudoku id with difficulty', () {
      final id = PuzzleId.parse('sudoku-2026-09-08-en-hard-v3');
      expect(id.difficulty, Difficulty.hard);
      expect(id.version, 3);
      expect(id.toString(), 'sudoku-2026-09-08-en-hard-v3');
    });

    test('rejects sudoku without difficulty and others with one', () {
      expect(() => PuzzleId.parse('sudoku-2026-09-08-en-v1'), throwsFormatException);
      expect(() => PuzzleId.parse('word-2026-09-08-en-easy-v1'), throwsFormatException);
    });

    test('rejects malformed ids', () {
      expect(PuzzleId.tryParse(''), isNull);
      expect(PuzzleId.tryParse('chess-2026-09-08-en-v1'), isNull);
      expect(PuzzleId.tryParse('word-2026-09-08-en'), isNull);
      expect(PuzzleId.tryParse('word-2026-02-30-en-v1'), isNull);
      expect(PuzzleId.tryParse('word-2026-09-08-EN-v1'), isNull);
      expect(PuzzleId.tryParse('word-2026-09-08-en-v1/../x'), isNull);
    });

    test('equality is by value', () {
      expect(PuzzleId.parse('letters-2026-09-08-en-v1'), PuzzleId.parse('letters-2026-09-08-en-v1'));
      expect(PuzzleId.parse('letters-2026-09-08-en-v1'), isNot(PuzzleId.parse('letters-2026-09-08-en-v2')));
    });
  });
}
