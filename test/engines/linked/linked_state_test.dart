import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/linked/linked.dart';

import 'fixtures.dart';

void main() {
  final puzzle = LinkedPuzzle.parse(flagPayload(), flagReveal());
  final initial = LinkedState.initial(puzzle);

  LinkedState solvedSets() => initial.guessSet(0, 'Green').guessSet(1, 'white').guessSet(2, 'Orange');

  test('starts with nothing solved and everything to play for', () {
    expect(initial.solvedSets, 0);
    expect(initial.isSolved, isFalse);
    expect(initial.isOver, isFalse);
    expect(initial.hints, 0);
    expect(initial.attempts, 0);
    expect(initial.wrongFinalGuesses, 0);
    expect(initial.points, 0);
    expect(initial.pointsOnOffer, 10);
    expect(initial.answerGiven(0), isNull);
  });

  test('a right answer locks a set, in any order, however it is spelled', () {
    final state = initial.guessSet(2, '  the ORANGE colour! ').guessSet(0, 'green');
    expect(state.isSetSolved(2), isTrue);
    expect(state.isSetSolved(0), isTrue);
    expect(state.isSetSolved(1), isFalse);
    expect(state.solvedSets, 2);
    expect(state.answerGiven(2), 'the ORANGE colour!');
    expect(state.attempts, 2);
    expect(state.points, 0, reason: 'points come only with the final subject');
  });

  test('a wrong answer at a set costs nothing and can be tried again', () {
    final state = initial.guessSet(0, 'blue').guessSet(0, 'Green');
    expect(state.isSetSolved(0), isTrue);
    expect(state.pointsOnOffer, 10);
    expect(state.attempts, 2);
  });

  test('an empty or repeated guess changes nothing, and a solved set is closed', () {
    expect(identical(initial.guessSet(0, '  '), initial), isTrue);
    final once = initial.guessSet(0, 'blue');
    expect(identical(once.guessSet(0, 'BLUE!'), once), isTrue);
    expect(once.alreadyGuessedAt(0, 'blue'), isTrue);
    expect(once.alreadyGuessedAt(1, 'blue'), isFalse);
    final solved = once.guessSet(0, 'Green');
    expect(identical(solved.guessSet(0, 'emerald'), solved), isTrue);
  });

  test('the final subject ends the puzzle and scores what is left', () {
    final state = solvedSets().guessFinal('the Irish flag');
    expect(state.isSolved, isTrue);
    expect(state.isOver, isTrue);
    expect(state.points, 10);
    expect(state.summary(), 'Solved · 10 of 10');
    expect(state.shareLines(), ['🔗 10/10', '🟩🟩🟩 → 🟩']);
  });

  test('each hint and each wrong final guess costs a point', () {
    final state = initial
        .showHint(0)
        .guessSet(0, 'Green')
        .showHint(LinkedState.finalHintIndex)
        .guessFinal('the flag of France')
        .guessFinal('Irish flag');
    expect(state.hints, 2);
    expect(state.wrongFinalGuesses, 1);
    expect(state.points, 7);
    expect(state.isSolved, isTrue);
    expect(state.summary(), 'Solved · 7 of 10 · 2 hints · 1 wrong guess');
    expect(state.shareLines(), ['🔗 7/10', '🟨🟥🟥 → 🟨']);
  });

  test('a solved puzzle never falls below one point', () {
    var state = initial;
    for (var i = 0; i < 4; i++) {
      state = state.showHint(i);
    }
    for (var i = 0; i < 8; i++) {
      state = state.guessFinal('wrong $i');
    }
    expect(state.hints, 4);
    expect(state.wrongFinalGuesses, 8);
    expect(state.pointsOnOffer, 1);
    state = state.guessFinal('The flag of Ireland');
    expect(state.points, 1);
  });

  test('a hint is not offered for a solved set, nor after the puzzle ends', () {
    final solved = initial.guessSet(0, 'Green');
    expect(identical(solved.showHint(0), solved), isTrue);
    final hinted = solved.showHint(1);
    expect(hinted.hints, 1);
    expect(identical(hinted.showHint(1), hinted), isTrue);
    final over = solvedSets().guessFinal('Irish flag');
    expect(identical(over.showHint(1), over), isTrue);
    expect(identical(over.guessFinal('anything else'), over), isTrue);
    expect(identical(over.guessSet(1, 'blue'), over), isTrue);
  });

  test('giving up ends the puzzle with nothing', () {
    final state = initial.guessSet(0, 'Green').giveUp();
    expect(state.gaveUp, isTrue);
    expect(state.isOver, isTrue);
    expect(state.isSolved, isFalse);
    expect(state.points, 0);
    expect(state.summary(), 'Not solved · 1 of 3 sets');
    expect(state.shareLines(), ['🔗 0/10', '🟩🟥🟥 → 🟥']);
    expect(identical(state.giveUp(), state), isTrue);
  });

  group('json', () {
    test('round trips a run of play', () {
      final state = initial.showHint(1).guessSet(1, 'nope').guessSet(1, 'White').guessFinal('wrong').guessFinal('Irish flag');
      final restored = LinkedState.fromJson(puzzle, state.toJson());
      expect(restored, state);
      expect(restored.points, 8);
      expect(LinkedState.fromJson(puzzle, initial.toJson()), initial);
    });

    test('rejects progress that could not have happened', () {
      Map<String, dynamic> progress(void Function(Map<String, dynamic>) change) {
        final json = initial.guessSet(0, 'blue').toJson();
        change(json);
        return json;
      }

      expect(() => LinkedState.fromJson(puzzle, progress((j) => j['sets'] = 'none')), throwsFormatException);
      expect(() => LinkedState.fromJson(puzzle, progress((j) => j['sets'] = <Object?>[<String>[], <String>[]])), throwsFormatException);
      expect(() => LinkedState.fromJson(puzzle, progress((j) => j['final'] = 'nope')), throwsFormatException);
      expect(() => LinkedState.fromJson(puzzle, progress((j) => j['hints'] = [true, false])), throwsFormatException);
      expect(() => LinkedState.fromJson(puzzle, progress((j) => j['hints'] = [1, 0, 0, 0])), throwsFormatException);
      expect(
        () => LinkedState.fromJson(puzzle, progress((j) => j['sets'] = <Object?>[<Object?>['blue', '  '], <String>[], <String>[]])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('no text'))),
      );
      expect(
        () => LinkedState.fromJson(puzzle, progress((j) => j['sets'] = <Object?>[<Object?>['blue', 'BLUE'], <String>[], <String>[]])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats the guess'))),
      );
      expect(
        () => LinkedState.fromJson(puzzle, progress((j) => j['sets'] = <Object?>[<Object?>['Green', 'blue'], <String>[], <String>[]])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('carries on after the right answer'))),
      );
      expect(
        () => LinkedState.fromJson(puzzle, progress((j) {
          j['final'] = <Object?>['Irish flag'];
          j['gaveUp'] = true;
        })),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('solves and gives up'))),
      );
    });
  });
}
