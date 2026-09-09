import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final word = PuzzleId.parse('word-2026-09-08-en-v1');
  final sudoku = PuzzleId.parse('sudoku-2026-09-08-en-medium-v1');
  final quiz = PuzzleId.parse('quiz-2026-09-08-en-v1');

  group('GameResult', () {
    test('challenge code round trips summary numbers only', () {
      final r = GameResult(
        puzzleId: sudoku,
        completedAt: DateTime.utc(2026, 9, 8, 10),
        solved: true,
        seconds: 523,
        hints: 2,
        shareLines: const ['secret grid'],
      );
      final code = r.challengeCode();
      expect(code, 's1.t523.h2');
      final back = GameResult.fromChallengeCode(sudoku, code)!;
      expect(back.solved, isTrue);
      expect(back.seconds, 523);
      expect(back.hints, 2);
      expect(back.shareLines, isEmpty);
    });

    test('malformed codes are ignored rather than thrown', () {
      expect(GameResult.fromChallengeCode(word, ''), isNull);
      expect(GameResult.fromChallengeCode(word, 'a'), isNull);
      expect(GameResult.fromChallengeCode(word, 's1.a-4'), isNull);
      expect(GameResult.fromChallengeCode(word, 's1.axyz'), isNull);
      final unknown = GameResult.fromChallengeCode(word, 's1.a4.z9');
      expect(unknown, isNotNull);
      expect(unknown!.attempts, 4);
    });

    test('summaries read naturally', () {
      expect(GameResult(puzzleId: word, completedAt: DateTime.utc(2026), solved: true, attempts: 4).summary(), 'Solved in 4/6');
      expect(GameResult(puzzleId: word, completedAt: DateTime.utc(2026), solved: false, attempts: 6).summary(), 'Not solved');
      expect(GameResult(puzzleId: sudoku, completedAt: DateTime.utc(2026), solved: true, seconds: 65, hints: 1).summary(),
          'Solved in 1:05 · 1 hint');
      expect(GameResult(puzzleId: quiz, completedAt: DateTime.utc(2026), solved: true, points: 4, maxPoints: 6).summary(),
          '4/6');
    });

    test('json round trip', () {
      final r = GameResult(
        puzzleId: quiz,
        completedAt: DateTime.utc(2026, 9, 8, 10, 5),
        solved: true,
        points: 5,
        maxPoints: 6,
        shareLines: const ['🟩🟩🟥🟩⭐🟩'],
        isArchivePlay: true,
      );
      expect(GameResult.fromJson(r.toJson()), r);
    });
  });
}
