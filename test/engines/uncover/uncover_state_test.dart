import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/uncover/uncover.dart';

import 'fixtures.dart';

void main() {
  final puzzle = boatPuzzle();
  UncoverState fresh() => UncoverState.initial(puzzle);

  int shown(UncoverState state) {
    var n = 0;
    for (var i = 0; i < puzzle.words.length; i++) {
      if (!puzzle.words[i].isSeparator && state.isRevealed(i)) n++;
    }
    return n;
  }

  test('a new state shows only the common words', () {
    final state = fresh();
    expect(state.isPlaying, isTrue);
    expect(state.isSolved, isFalse);
    expect(state.guessCount, 0);
    expect(state.hintsUsed, 0);
    expect(state.revealedCount, 0);
    expect(state.hiddenCount, 49);
    expect(state.points, 0, reason: 'nothing is scored until it is solved');
    expect(shown(state), puzzle.wordCount - puzzle.hiddenCount - puzzle.subjectCount);
  });

  test('a guess opens every occurrence of the word', () {
    final state = fresh().submit('Sheets');
    expect(state.guessCount, 1);
    expect(state.lastGuess!.word, 'Sheets');
    expect(state.lastGuess!.matches, 2);
    expect(state.revealedCount, 2);
    expect(state.hasGuessed('sheet'), isTrue);
    for (var i = 0; i < puzzle.words.length; i++) {
      if (puzzle.words[i].normalised == 'sheet') {
        expect(state.isRevealed(i), isTrue);
        expect(state.isLatest(i), isTrue);
      }
    }
  });

  test('a word that is not there still counts as a guess', () {
    final state = fresh().submit('canoe');
    expect(state.guessCount, 1);
    expect(state.lastGuess!.matches, 0);
    expect(state.revealedCount, 0);
  });

  test('empty, common and repeated guesses are refused', () {
    final state = fresh().submit('hull');
    expect(state.check('  '), UncoverCheck.empty);
    expect(state.check('the'), UncoverCheck.common);
    expect(state.check('Hulls'), UncoverCheck.repeat);
    expect(state.check('prow'), UncoverCheck.ok);
    expect(identical(state.submit('  '), state), isTrue);
    expect(identical(state.submit('the'), state), isTrue);
    expect(identical(state.submit('hull'), state), isTrue);
    expect(state.submit('prow').guessCount, 2);
  });

  test('guessing a word of the subject opens nothing', () {
    var state = fresh().submit('paper').submit('boats').submit('ship');
    expect(state.guessCount, 3);
    expect(state.revealedCount, 0);
    expect(state.isSolved, isFalse);
    for (var i = 0; i < puzzle.words.length; i++) {
      if (puzzle.words[i].isSubject) expect(state.isRevealed(i), isFalse);
    }
    state = state.submit('paper boat');
    expect(state.isSolved, isTrue);
    for (var i = 0; i < puzzle.words.length; i++) {
      if (puzzle.words[i].isSubject) expect(state.isRevealed(i), isTrue);
    }
  });

  test('naming the subject by any alias solves it', () {
    for (final answer in ['Paper Boat', 'the paper boats', 'paper ship']) {
      final state = fresh().submit(answer);
      expect(state.isSolved, isTrue, reason: answer);
      expect(state.isOver, isTrue);
      expect(state.lastGuess!.matches, 0);
      expect(state.guessCount, 1);
    }
  });

  test('hints run out and each one costs a point', () {
    var state = fresh();
    for (var i = 0; i < puzzle.hints.length; i++) {
      expect(state.canHint, isTrue);
      state = state.useHint();
      expect(state.revealedHints, puzzle.hints.take(i + 1));
    }
    expect(state.canHint, isFalse);
    expect(identical(state.useHint(), state), isTrue);
    expect(state.submit('paper boat').points, UncoverState.maxPoints - 3);
  });

  test('points fall by one for every five guesses and never below one', () {
    var state = fresh();
    for (final word in ['hull', 'prow', 'puddle', 'fibre', 'voyage']) {
      state = state.submit(word);
    }
    expect(state.submit('paper boat').points, UncoverState.maxPoints - 1, reason: 'six guesses including the answer');
    var many = fresh();
    for (var i = 0; i < 60; i++) {
      many = many.submit('word$i');
    }
    expect(many.submit('paper boat').points, 1);
  });

  test('giving up opens everything and scores nothing', () {
    final state = fresh().submit('hull').giveUp();
    expect(state.isOver, isTrue);
    expect(state.isSolved, isFalse);
    expect(state.points, 0);
    expect(shown(state), puzzle.wordCount);
    expect(identical(state.submit('paper boat'), state), isTrue);
    expect(identical(state.giveUp(), state), isTrue);
  });

  test('the share lines and the summary say nothing about the subject', () {
    final solved = fresh().submit('hull').useHint().submit('paper boat');
    expect(solved.summary(), 'Uncovered in 2 guesses · 1 hint');
    expect(solved.shareLines(), ['🔎 uncovered in 2 guesses · 1 hint', '🟩🟩🟩🟩🟩🟩🟩🟩🟩⬜']);
    expect(solved.shareLines().join(), isNot(contains('aper')));
    final gaveUp = fresh().submit('hull').giveUp();
    expect(gaveUp.summary(), 'Not uncovered · 1 guess');
    expect(gaveUp.shareLines(), ['🔎 not uncovered · 1 guess']);
  });

  group('progress', () {
    test('round trips through json', () {
      final state = fresh().submit('hull').useHint().submit('canoe');
      final back = UncoverState.fromJson(puzzle, state.toJson());
      expect(back.toJson(), state.toJson());
      expect(back.guessCount, 2);
      expect(back.hintsUsed, 1);
      expect(back.revealedCount, state.revealedCount);
      expect(back.isPlaying, isTrue);
    });

    test('round trips a finished game', () {
      for (final state in [fresh().submit('hull').submit('paper boat'), fresh().submit('hull').giveUp()]) {
        final back = UncoverState.fromJson(puzzle, state.toJson());
        expect(back.status, state.status);
        expect(back.isSolved, state.isSolved);
        expect(back.points, state.points);
      }
    });

    test('refuses malformed data', () {
      expect(() => UncoverState.fromJson(puzzle, const {}), throwsFormatException);
      expect(() => UncoverState.fromJson(puzzle, const {'guesses': [], 'hints': 0, 'status': 'won'}), throwsFormatException);
      expect(() => UncoverState.fromJson(puzzle, const {'guesses': [], 'hints': -1, 'status': 'playing'}), throwsFormatException);
      expect(() => UncoverState.fromJson(puzzle, const {'guesses': [], 'hints': 9, 'status': 'playing'}), throwsFormatException);
      expect(() => UncoverState.fromJson(puzzle, const {'guesses': ['hull'], 'hints': 0, 'status': 'playing'}), throwsFormatException);
      expect(
        () => UncoverState.fromJson(puzzle, const {
          'guesses': [
            ['hull', 1],
          ],
          'hints': 0,
          'status': 'solved',
        }),
        throwsFormatException,
        reason: 'solved without the subject',
      );
    });
  });
}
