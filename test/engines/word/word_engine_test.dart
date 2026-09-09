import 'package:playthepaper/engines/word/word_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const c = LetterFeedback.correct;
  const m = LetterFeedback.misplaced;
  const a = LetterFeedback.absent;

  Map<String, dynamic> payload({int length = 6, String first = 'S', int max = 6}) => {
    'length': length,
    'firstLetter': first,
    'maxGuesses': max,
  };

  final stream = WordPuzzle.parse(payload(), {'answer': 'STREAM'});

  group('WordPuzzle.parse', () {
    test('accepts a valid payload and reveal', () {
      expect(stream.length, 6);
      expect(stream.firstLetter, 'S');
      expect(stream.maxGuesses, 6);
      expect(stream.answer, 'STREAM');
      expect(stream.toPayload(), payload());
      expect(stream.toReveal(), {'answer': 'STREAM'});
    });

    test('rejects a lowercase or non-letter answer', () {
      expect(() => WordPuzzle.parse(payload(), {'answer': 'stream'}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(), {'answer': 'STRE4M'}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(), {'answer': ''}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(), {}), throwsFormatException);
    });

    test('rejects an answer of the wrong length', () {
      expect(() => WordPuzzle.parse(payload(), {'answer': 'STREAMS'}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(length: 5), {'answer': 'STREAM'}), throwsFormatException);
    });

    test('rejects an answer that does not start with the first letter', () {
      expect(() => WordPuzzle.parse(payload(first: 'T'), {'answer': 'STREAM'}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(first: 's'), {'answer': 'STREAM'}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(first: 'ST'), {'answer': 'STREAM'}), throwsFormatException);
    });

    test('rejects bad counts', () {
      expect(() => WordPuzzle.parse(payload(max: 0), {'answer': 'STREAM'}), throwsFormatException);
      expect(() => WordPuzzle.parse(payload(length: 0), {'answer': ''}), throwsFormatException);
      expect(
        () => WordPuzzle.parse({'length': '6', 'firstLetter': 'S', 'maxGuesses': 6}, {'answer': 'STREAM'}),
        throwsFormatException,
      );
    });
  });

  group('evaluateGuess', () {
    test('STREAM against STREAM is all correct', () {
      expect(evaluateGuess('STREAM', 'STREAM'), [c, c, c, c, c, c]);
    });

    test('no shared letters is all absent', () {
      expect(evaluateGuess('BUNKED', 'STRAWY'), [a, a, a, a, a, a]);
    });

    test('SEEDED against SPEEDS: exact S and E first, then misplaced E and D left to right, extra E and D absent', () {
      // Exact: S(0) and E(2). Remaining answer letters: P, E, D, S.
      // Left to right over the rest: E(1) takes the spare E, D(3) takes the
      // spare D, then E(4) and D(5) find nothing left.
      expect(evaluateGuess('SEEDED', 'SPEEDS'), [c, m, c, m, a, a]);
    });

    test('NANANA against BANANA: only the leading N is absent because every N of the answer is matched exactly', () {
      expect(evaluateGuess('NANANA', 'BANANA'), [a, c, c, c, c, c]);
    });

    test('more copies of a letter than the answer: only the one exact E is marked', () {
      expect(evaluateGuess('SMEEEE', 'STREAM'), [c, m, a, c, a, a]);
    });

    test('an exact match to the right beats an earlier copy of the same letter', () {
      expect(evaluateGuess('SAAAAM', 'STREAM'), [c, a, a, a, c, c]);
    });

    test('misplaced marks are limited to the count of unmatched answer letters', () {
      expect(evaluateGuess('ELLIES', 'SELLER'), [m, m, c, a, c, m]);
      expect(evaluateGuess('LLLLLL', 'SELLER'), [a, a, c, c, a, a]);
    });

    test('all misplaced when every letter is present but shifted', () {
      expect(evaluateGuess('TREAMS', 'STREAM'), [m, m, m, m, m, m]);
    });

    test('rejects a guess of a different length', () {
      expect(() => evaluateGuess('STREAMS', 'STREAM'), throwsArgumentError);
    });
  });

  group('validateGuess', () {
    final dictionary = {'STREAM', 'STRAND', 'TRAINS'};

    test('ok for a listed word with the given first letter', () {
      expect(validateGuess('STRAND', puzzle: stream, dictionary: dictionary), GuessValidation.ok);
      expect(validateGuess('strand', puzzle: stream, dictionary: dictionary), GuessValidation.ok);
      expect(GuessValidation.ok.message, isNull);
    });

    test('too short', () {
      final v = validateGuess('STRA', puzzle: stream, dictionary: dictionary);
      expect(v, GuessValidation.tooShort);
      expect(v.message, isNotEmpty);
    });

    test('wrong first letter', () {
      final v = validateGuess('TRAINS', puzzle: stream, dictionary: dictionary);
      expect(v, GuessValidation.wrongFirstLetter);
      expect(v.message, isNotEmpty);
    });

    test('not in list', () {
      final v = validateGuess('STRXYZ', puzzle: stream, dictionary: dictionary);
      expect(v, GuessValidation.notInList);
      expect(v.message, isNotEmpty);
      expect(validateGuess('STREAMS', puzzle: stream, dictionary: dictionary), GuessValidation.notInList);
    });
  });

  group('WordState', () {
    test('starts empty and playing', () {
      final s = WordState.initial(stream);
      expect(s.guesses, isEmpty);
      expect(s.feedbacks, isEmpty);
      expect(s.status, WordStatus.playing);
      expect(s.isOver, isFalse);
    });

    test('submit records the guess and its feedback without mutating the old state', () {
      final s0 = WordState.initial(stream);
      final s1 = s0.submit('strand');
      expect(s0.guesses, isEmpty);
      expect(s1.guesses, ['STRAND']);
      expect(s1.feedbacks, [
        [c, c, c, m, a, a],
      ]);
      expect(s1.status, WordStatus.playing);
    });

    test('submit rejects the wrong length or non-letters', () {
      final s = WordState.initial(stream);
      expect(() => s.submit('STRAN'), throwsArgumentError);
      expect(() => s.submit('STRAN1'), throwsArgumentError);
    });

    test('wins when the answer is guessed', () {
      final s = WordState.initial(stream).submit('STRAND').submit('STREAM');
      expect(s.status, WordStatus.won);
      expect(s.isOver, isTrue);
      expect(() => s.submit('STRAND'), throwsStateError);
    });

    test('loses after maxGuesses wrong guesses', () {
      var s = WordState.initial(stream);
      for (var i = 0; i < 5; i++) {
        s = s.submit('STRAND');
        expect(s.status, WordStatus.playing);
      }
      s = s.submit('STRAND');
      expect(s.status, WordStatus.lost);
      expect(() => s.submit('STREAM'), throwsStateError);
    });

    test('a win on the last guess is a win', () {
      var s = WordState.initial(stream);
      for (var i = 0; i < 5; i++) {
        s = s.submit('STRAND');
      }
      expect(s.submit('STREAM').status, WordStatus.won);
    });

    test('keyStates: correct beats misplaced beats absent', () {
      // STRAND: S T R correct, A misplaced, N D absent.
      // TRAINS: T R A S misplaced, I N absent.
      // SMEARS: S correct, M E A R misplaced, final S absent.
      final s = WordState.initial(stream).submit('STRAND').submit('TRAINS').submit('SMEARS');
      final keys = s.keyStates();
      expect(keys['S'], WordKeyState.correct);
      expect(keys['T'], WordKeyState.correct);
      expect(keys['R'], WordKeyState.correct);
      expect(keys['A'], WordKeyState.misplaced);
      expect(keys['M'], WordKeyState.misplaced);
      expect(keys['E'], WordKeyState.misplaced);
      expect(keys['N'], WordKeyState.absent);
      expect(keys['D'], WordKeyState.absent);
      expect(keys['I'], WordKeyState.absent);
      expect(keys.containsKey('Z'), isFalse);
    });

    test('keyStates upgrades on a better guess and never downgrades on a worse one', () {
      // SMEARS: M and A misplaced. SAAAAM: A and M correct.
      final up = WordState.initial(stream).submit('SMEARS').submit('SAAAAM');
      expect(up.keyStates()['M'], WordKeyState.correct);
      expect(up.keyStates()['A'], WordKeyState.correct);
      final down = WordState.initial(stream).submit('SAAAAM').submit('SMEARS');
      expect(down.keyStates()['M'], WordKeyState.correct);
      expect(down.keyStates()['A'], WordKeyState.correct);
      // SEEDED then SMEARS: E is misplaced in both, never absent.
      final kept = WordState.initial(stream).submit('SEEDED').submit('SMEARS');
      expect(kept.keyStates()['E'], WordKeyState.misplaced);
      expect(kept.keyStates()['D'], WordKeyState.absent);
    });

    test('shareLines gives one emoji row per guess', () {
      final s = WordState.initial(stream).submit('STRAND').submit('SEEDED').submit('STREAM');
      expect(s.shareLines(), ['🟩🟩🟩🟨⬜⬜', '🟩🟨⬜⬜⬜⬜', '🟩🟩🟩🟩🟩🟩']);
    });

    test('json round trip keeps guesses, feedback and status', () {
      final s = WordState.initial(stream).submit('STRAND').submit('STREAM');
      final json = s.toJson();
      expect(json, {
        'guesses': ['STRAND', 'STREAM'],
      });
      final back = WordState.fromJson(stream, json);
      expect(back, s);
      expect(back.status, WordStatus.won);
      expect(back.feedbacks, s.feedbacks);
      expect(WordState.fromJson(stream, {'guesses': <String>[]}), WordState.initial(stream));
    });

    test('fromJson rejects guesses that cannot belong to the puzzle', () {
      expect(() => WordState.fromJson(stream, {}), throwsFormatException);
      expect(() => WordState.fromJson(stream, {'guesses': 'STRAND'}), throwsFormatException);
      expect(
        () => WordState.fromJson(stream, {
          'guesses': ['STRAN'],
        }),
        throwsFormatException,
      );
      expect(
        () => WordState.fromJson(stream, {
          'guesses': ['strand'],
        }),
        throwsFormatException,
      );
      expect(
        () => WordState.fromJson(stream, {
          'guesses': ['STREAM', 'STRAND'],
        }),
        throwsFormatException,
      );
      expect(() => WordState.fromJson(stream, {'guesses': List.filled(7, 'STRAND')}), throwsFormatException);
    });
  });
}
