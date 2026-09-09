import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues.dart';

import 'fixtures.dart';

void main() {
  final puzzle = FiveCluesPuzzle.parse(honeyPayload(), honeyReveal());
  final initial = FiveCluesState.initial(puzzle);

  FiveCluesState afterWrongGuesses(int count) {
    var state = initial;
    for (var i = 0; i < count; i++) {
      state = state.guess('wrong $i');
    }
    return state;
  }

  test('starts on the first clue with nothing guessed', () {
    expect(initial.revealed, 1);
    expect(initial.currentClue, 0);
    expect(initial.visibleClues, [puzzle.clues.first]);
    expect(initial.guesses, isEmpty);
    expect(initial.attempts, 0);
    expect(initial.isOver, isFalse);
    expect(initial.isSolved, isFalse);
    expect(initial.pointsOnOffer, 5);
    expect(initial.points, 0);
    expect(initial.solvedOnClue, isNull);
  });

  test('a wrong guess is recorded and brings out the next clue', () {
    final state = initial.guess('Nectar');
    expect(state.attempts, 1);
    expect(state.guesses.single.text, 'Nectar');
    expect(state.guesses.single.clue, 0);
    expect(state.guesses.single.correct, isFalse);
    expect(state.revealed, 2);
    expect(state.visibleClues, hasLength(2));
    expect(state.isOver, isFalse);
    expect(state.pointsOnOffer, 4);
  });

  test('a right answer ends the puzzle and scores by the clue it came on', () {
    final state = initial.guess('Nectar').guess('  the HONEY! ');
    expect(state.isSolved, isTrue);
    expect(state.isOver, isTrue);
    expect(state.solvedOnClue, 1);
    expect(state.points, 4);
    expect(state.attempts, 2);
    expect(state.revealed, 2, reason: 'a right answer does not open another clue');
    expect(state.summary(), 'Solved on clue 2 · 4 points');
    expect(state.shareLines(), ['🔗 solved on clue 2', '🟥🟩⬜⬜⬜']);
  });

  test('an alias solves it too, and the first clue is worth five', () {
    final state = initial.guess('Runny Honey');
    expect(state.isSolved, isTrue);
    expect(state.points, 5);
    expect(state.summary(), 'Solved on clue 1 · 5 points');
  });

  test('a pass shows the next clue without counting as an attempt', () {
    final state = initial.pass().pass();
    expect(state.revealed, 3);
    expect(state.attempts, 0);
    expect(state.pointsOnOffer, 3);
    expect(state.isOver, isFalse);
  });

  test('a wrong guess on the last clue ends the puzzle with nothing', () {
    final state = afterWrongGuesses(5);
    expect(state.revealed, 5);
    expect(state.attempts, 5);
    expect(state.isOver, isTrue);
    expect(state.isSolved, isFalse);
    expect(state.gaveUp, isTrue);
    expect(state.points, 0);
    expect(state.summary(), 'Not solved · the answer was revealed');
    expect(state.shareLines(), ['🔗 not solved', '🟥🟥🟥🟥🟥']);
  });

  test('a pass on the last clue gives up', () {
    final state = initial.pass().pass().pass().pass().pass();
    expect(state.revealed, 5);
    expect(state.gaveUp, isTrue);
    expect(state.attempts, 0);
    expect(state.points, 0);
  });

  test('an empty, repeated or post-mortem guess changes nothing', () {
    expect(identical(initial.guess('   '), initial), isTrue);
    expect(identical(initial.guess('!!'), initial), isTrue);
    final once = initial.guess('Nectar');
    expect(identical(once.guess('  nectar  '), once), isTrue);
    expect(once.alreadyGuessed('NECTAR!'), isTrue);
    expect(once.alreadyGuessed('sugar'), isFalse);
    final solved = initial.guess('Honey');
    expect(identical(solved.guess('Nectar'), solved), isTrue);
    expect(identical(solved.pass(), solved), isTrue);
  });

  group('json', () {
    test('round trips a run of play', () {
      final state = initial.guess('Nectar').pass().guess('Honey');
      final restored = FiveCluesState.fromJson(puzzle, state.toJson());
      expect(restored, state);
      expect(restored.points, 3);
      expect(FiveCluesState.fromJson(puzzle, initial.toJson()), initial);
      expect(FiveCluesState.fromJson(puzzle, afterWrongGuesses(5).toJson()).gaveUp, isTrue);
    });

    test('rejects progress that could not have happened', () {
      Map<String, dynamic> progress(void Function(Map<String, dynamic>) change) {
        final json = initial.guess('Nectar').toJson();
        change(json);
        return json;
      }

      expect(() => FiveCluesState.fromJson(puzzle, progress((j) => j['revealed'] = 0)), throwsFormatException);
      expect(() => FiveCluesState.fromJson(puzzle, progress((j) => j['revealed'] = 6)), throwsFormatException);
      expect(() => FiveCluesState.fromJson(puzzle, progress((j) => j['revealed'] = 'two')), throwsFormatException);
      expect(() => FiveCluesState.fromJson(puzzle, progress((j) => j['guesses'] = 'none')), throwsFormatException);
      expect(() => FiveCluesState.fromJson(puzzle, progress((j) => j['guesses'] = <Object?>['nectar'])), throwsFormatException);
      expect(
        () => FiveCluesState.fromJson(puzzle, progress((j) => (j['guesses'] as List)[0] = {'text': 'x', 'clue': 4})),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('was not shown'))),
      );
      expect(
        () => FiveCluesState.fromJson(puzzle, progress((j) => (j['guesses'] as List)[0] = {'text': '  ', 'clue': 0})),
        throwsFormatException,
      );
      expect(
        () => FiveCluesState.fromJson(puzzle, progress((j) => (j['guesses'] as List)[0]['correct'] = true)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('disagrees'))),
      );
      expect(
        () => FiveCluesState.fromJson(puzzle, progress((j) => j['gaveUp'] = true)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('before the last clue'))),
      );
    });

    test('rejects guesses out of order or after a right answer', () {
      final json = initial.guess('Nectar').pass().guess('Sugar').toJson();
      (json['guesses'] as List)[1]['clue'] = 0;
      (json['guesses'] as List)[0]['clue'] = 1;
      expect(
        () => FiveCluesState.fromJson(puzzle, json),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('out of order'))),
      );

      final solvedThenMore = {
        'revealed': 2,
        'gaveUp': false,
        'guesses': [
          {'text': 'Honey', 'clue': 0},
          {'text': 'Sugar', 'clue': 1},
        ],
      };
      expect(
        () => FiveCluesState.fromJson(puzzle, solvedThenMore),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('carries on'))),
      );
    });

    test('rejects more wrong guesses than clues shown', () {
      final json = {
        'revealed': 2,
        'gaveUp': false,
        'guesses': [
          {'text': 'Sugar', 'clue': 0},
          {'text': 'Nectar', 'clue': 1},
        ],
      };
      expect(
        () => FiveCluesState.fromJson(puzzle, json),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('more wrong guesses'))),
      );
    });
  });
}
