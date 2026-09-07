import 'package:daypencil/engines/quiz/quiz_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> question(int n, {List<String>? options, String? prompt, String? storyId}) => {
    'prompt': prompt ?? 'Question $n?',
    'options': options ?? ['A$n', 'B$n', 'C$n', 'D$n'],
    'storyId': storyId ?? 'story-$n',
  };

  Map<String, dynamic> payload({List<Map<String, dynamic>>? questions, Object? wager}) => {
    'questions': questions ?? [for (var n = 1; n <= 5; n++) question(n)],
    'wagerQuestion': ?wager,
  };

  Map<String, dynamic> reveal({List<Object?>? answers, List<Object?>? explanations}) => {
    'answers': answers ?? [0, 1, 2, 3, 0],
    'explanations': explanations ?? [for (var n = 1; n <= 5; n++) 'Because $n. And so on.'],
  };

  final puzzle = QuizPuzzle.parse(payload(), reveal());

  group('QuizPuzzle.parse', () {
    test('accepts a valid payload and reveal', () {
      expect(puzzle.questions, hasLength(5));
      expect(puzzle.questions[2].prompt, 'Question 3?');
      expect(puzzle.questions[2].options, ['A3', 'B3', 'C3', 'D3']);
      expect(puzzle.questions[2].storyId, 'story-3');
      expect(puzzle.wagerQuestion, 4);
      expect(puzzle.maxPoints, 6);
      expect(puzzle.answerOf(1), 1);
      expect(puzzle.explanationOf(4), 'Because 5. And so on.');
      expect(puzzle.toPayload(), payload(wager: 4));
      expect(puzzle.toReveal(), reveal());
    });

    test('reads an explicit wager question', () {
      expect(QuizPuzzle.parse(payload(wager: 2), reveal()).wagerQuestion, 2);
      expect(QuizPuzzle.parse(payload(wager: 0), reveal()).wagerQuestion, 0);
    });

    test('rejects a wager question out of range or of the wrong type', () {
      expect(() => QuizPuzzle.parse(payload(wager: 5), reveal()), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(wager: -1), reveal()), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(wager: '4'), reveal()), throwsFormatException);
    });

    test('rejects any number of questions but five', () {
      final four = [for (var n = 1; n <= 4; n++) question(n)];
      final six = [for (var n = 1; n <= 6; n++) question(n)];
      expect(() => QuizPuzzle.parse(payload(questions: four), reveal()), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(questions: six), reveal()), throwsFormatException);
      expect(() => QuizPuzzle.parse({}, reveal()), throwsFormatException);
    });

    test('rejects a question with an empty prompt or story id', () {
      final blank = [question(1, prompt: ' '), for (var n = 2; n <= 5; n++) question(n)];
      expect(() => QuizPuzzle.parse(payload(questions: blank), reveal()), throwsFormatException);
      final noStory = [question(1, storyId: ''), for (var n = 2; n <= 5; n++) question(n)];
      expect(() => QuizPuzzle.parse(payload(questions: noStory), reveal()), throwsFormatException);
      final missing = [question(1)..remove('storyId'), for (var n = 2; n <= 5; n++) question(n)];
      expect(() => QuizPuzzle.parse(payload(questions: missing), reveal()), throwsFormatException);
    });

    test('rejects options that are not four, not distinct or empty', () {
      List<Map<String, dynamic>> withOptions(List<String> options) => [
        question(1, options: options),
        for (var n = 2; n <= 5; n++) question(n),
      ];
      expect(() => QuizPuzzle.parse(payload(questions: withOptions(['a', 'b', 'c'])), reveal()), throwsFormatException);
      expect(
        () => QuizPuzzle.parse(payload(questions: withOptions(['a', 'b', 'c', 'd', 'e'])), reveal()),
        throwsFormatException,
      );
      expect(
        () => QuizPuzzle.parse(payload(questions: withOptions(['a', 'b', 'c', 'a'])), reveal()),
        throwsFormatException,
      );
      expect(
        () => QuizPuzzle.parse(payload(questions: withOptions(['a', 'b', 'c', ''])), reveal()),
        throwsFormatException,
      );
    });

    test('rejects answers that are not five indexes from 0 to 3', () {
      expect(() => QuizPuzzle.parse(payload(), reveal(answers: [0, 1, 2, 3])), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(), reveal(answers: [0, 1, 2, 3, 4])), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(), reveal(answers: [0, 1, 2, 3, -1])), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(), reveal(answers: [0, 1, 2, 3, '0'])), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(), {'explanations': reveal()['explanations']}), throwsFormatException);
    });

    test('rejects explanations that are not five non-empty strings', () {
      final four = [for (var n = 1; n <= 4; n++) 'Because $n.'];
      expect(() => QuizPuzzle.parse(payload(), reveal(explanations: four)), throwsFormatException);
      final blank = [...four, ''];
      expect(() => QuizPuzzle.parse(payload(), reveal(explanations: blank)), throwsFormatException);
      final wrongType = [...four, 5];
      expect(() => QuizPuzzle.parse(payload(), reveal(explanations: wrongType)), throwsFormatException);
      expect(() => QuizPuzzle.parse(payload(), {'answers': reveal()['answers']}), throwsFormatException);
    });

    test('error messages say which question is wrong', () {
      final bad = [question(1), question(2), question(3, prompt: ''), question(4), question(5)];
      expect(
        () => QuizPuzzle.parse(payload(questions: bad), reveal()),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('question 3'))),
      );
    });
  });

  group('QuizState', () {
    final fresh = QuizState.initial(puzzle);

    QuizState play(List<int> options, {bool stakeBeforeWager = false}) {
      var s = QuizState.initial(puzzle);
      for (final o in options) {
        if (stakeBeforeWager && s.current == puzzle.wagerQuestion) s = s.stake();
        s = s.answer(o);
      }
      return s;
    }

    test('starts unanswered with no points', () {
      expect(fresh.answers, [null, null, null, null, null]);
      expect(fresh.current, 0);
      expect(fresh.points, 0);
      expect(fresh.staked, isFalse);
      expect(fresh.canStake, isFalse);
      expect(fresh.isFinished, isFalse);
    });

    test('answers advance in order and score one point each when right', () {
      final s = play([0, 0, 2]);
      expect(s.current, 3);
      expect(s.isCorrect(0), isTrue);
      expect(s.isCorrect(1), isFalse);
      expect(s.isCorrect(2), isTrue);
      expect(s.pointsFor(1), 0);
      expect(s.points, 2);
      expect(s.isFinished, isFalse);
      expect(fresh.answers, [null, null, null, null, null], reason: 'states are immutable');
    });

    test('rejects an option out of range', () {
      expect(() => fresh.answer(4), throwsArgumentError);
      expect(() => fresh.answer(-1), throwsArgumentError);
    });

    test('a finished quiz ignores further answers', () {
      final s = play([0, 1, 2, 3, 0]);
      expect(s.isFinished, isTrue);
      expect(s.current, 5);
      expect(s.points, 5);
      expect(s.answer(1), same(s));
    });

    test('the stake is offered only at the wager question with a point in hand', () {
      expect(play([0, 1, 2]).canStake, isFalse, reason: 'not yet the wager question');
      expect(play([1, 0, 3, 0]).canStake, isFalse, reason: 'no points to stake');
      expect(play([1, 0, 3, 0]).stake().staked, isFalse);
      expect(play([0, 0, 0, 0]).canStake, isTrue);
      expect(play([0, 0, 0, 0]).stake().staked, isTrue);
      expect(play([0, 1, 2, 3, 0]).canStake, isFalse, reason: 'already answered');
    });

    test('a staked right answer scores two, a staked wrong answer loses one', () {
      final right = play([0, 1, 2, 3, 0], stakeBeforeWager: true);
      expect(right.staked, isTrue);
      expect(right.pointsFor(4), 2);
      expect(right.points, 6);

      final wrong = play([0, 1, 2, 3, 1], stakeBeforeWager: true);
      expect(wrong.pointsFor(4), -1);
      expect(wrong.points, 3);

      final unstaked = play([0, 1, 2, 3, 1]);
      expect(unstaked.points, 4);
    });

    test('points never drop below zero', () {
      final s = play([0, 0, 1, 1, 1], stakeBeforeWager: true);
      expect(s.staked, isTrue);
      expect(s.points, 0);
    });

    test('a stake can be withdrawn before the wager is answered, not after', () {
      final staked = play([0, 0, 0, 0]).stake();
      expect(staked.unstake().staked, isFalse);
      expect(staked.unstake().canStake, isTrue);
      final answered = staked.answer(0);
      expect(answered.unstake(), same(answered));
      expect(answered.stake(), same(answered));
      expect(fresh.unstake(), same(fresh));
    });

    test('an earlier wager question is honoured', () {
      final early = QuizPuzzle.parse(payload(wager: 1), reveal());
      var s = QuizState.initial(early).answer(0);
      expect(s.canStake, isTrue);
      s = s.stake().answer(3);
      expect(s.points, 0);
      s = s.answer(2).answer(3).answer(0);
      expect(s.points, 3);
      expect(s.shareLine(), '🟩⭐🟥🟩🟩🟩');
    });

    test('shareLine marks each question and stars the wager when staked', () {
      expect(play([0, 0, 2, 3, 1]).shareLine(), '🟩🟥🟩🟩🟥');
      expect(play([0, 0, 2, 3, 0], stakeBeforeWager: true).shareLine(), '🟩🟥🟩🟩⭐🟩');
      expect(play([0, 0, 2, 3, 1], stakeBeforeWager: true).shareLine(), '🟩🟥🟩🟩⭐🟥');
      expect(play([0, 1]).shareLine(), '🟩🟩⬜⬜⬜');
    });

    test('toJson round-trips through fromJson', () {
      for (final s in [
        fresh,
        play([0, 3]),
        play([0, 1, 2, 3]).stake(),
        play([0, 1, 2, 3, 0], stakeBeforeWager: true),
        play([1, 1, 1, 1, 1]),
      ]) {
        expect(QuizState.fromJson(puzzle, s.toJson()), s);
      }
      expect(play([0, 3]).toJson(), {
        'answers': [0, 3, null, null, null],
        'staked': false,
      });
    });

    test('fromJson treats a missing staked flag as false', () {
      expect(
        QuizState.fromJson(puzzle, {
          'answers': [0, null, null, null, null],
        }),
        play([0]),
      );
    });

    test('fromJson rejects an answers list of the wrong length', () {
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [0, 1, 2, 3],
          'staked': false,
        }),
        throwsFormatException,
      );
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [0, 1, 2, 3, 0, 1],
          'staked': false,
        }),
        throwsFormatException,
      );
      expect(() => QuizState.fromJson(puzzle, {'staked': false}), throwsFormatException);
    });

    test('fromJson rejects bad answers, gaps and impossible stakes', () {
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [0, 4, null, null, null],
          'staked': false,
        }),
        throwsFormatException,
      );
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [0, null, 2, null, null],
          'staked': false,
        }),
        throwsFormatException,
      );
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [1, 0, 3, 0, null],
          'staked': true,
        }),
        throwsFormatException,
        reason: 'no point to stake',
      );
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [0, null, null, null, null],
          'staked': true,
        }),
        throwsFormatException,
        reason: 'the wager question is not reached',
      );
      expect(
        () => QuizState.fromJson(puzzle, {
          'answers': [0, 1, 2, 3, null],
          'staked': 'yes',
        }),
        throwsFormatException,
      );
    });
  });

  group('QuizMarks', () {
    test('reads a share line back', () {
      final marks = QuizMarks.parse('🟩🟥🟩🟩⭐🟥');
      expect(marks.marks, [true, false, true, true, false]);
      expect(marks.staked, isTrue);
      expect(marks[1], isFalse);
      expect(marks[7], isNull);
      expect(QuizMarks.parse('🟩🟩⬜⬜⬜'), const QuizMarks(marks: [true, true, null, null, null], staked: false));
      expect(QuizMarks.parse(''), const QuizMarks(marks: [], staked: false));
    });

    test('matches the marks of the state that wrote the line', () {
      var s = QuizState.initial(puzzle).answer(0).answer(0).answer(2).answer(3);
      expect(QuizMarks.parse(s.shareLine()), QuizMarks.of(s));
      s = s.stake().answer(1);
      expect(QuizMarks.parse(s.shareLine()), QuizMarks.of(s));
      expect(QuizMarks.of(s).staked, isTrue);
    });
  });
}
