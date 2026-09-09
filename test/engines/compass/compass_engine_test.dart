import 'package:playthepaper/engines/compass/compass_engine.dart';
import 'package:test/test.dart';

/// A distinct lowercase word for each index, for large synthetic puzzles.
String syntheticWord(int i) {
  var n = i;
  final out = StringBuffer();
  do {
    out.writeCharCode('a'.codeUnitAt(0) + n % 26);
    n ~/= 26;
  } while (n > 0);
  return out.toString();
}

void main() {
  const words = ['port', 'dock', 'ship', 'boat', 'pier', 'quay', 'sea', 'wharf', 'marina', 'anchor'];
  Map<String, int> ranksOf(List<String> list) => {for (var i = 0; i < list.length; i++) list[i]: i + 1};
  final ranks = ranksOf(words);
  final puzzle = CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': ranks});

  group('CompassPuzzle.parse', () {
    test('accepts a valid payload and reveal', () {
      expect(puzzle.target, 'harbor');
      expect(puzzle.vocabularySize, 10);
      expect(puzzle.ranks, ranks);
      expect(puzzle.wordAt(1), 'port');
      expect(puzzle.wordAt(10), 'anchor');
      expect(puzzle.toPayload(), {'vocabularySize': 10});
      expect(puzzle.toReveal(), {'target': 'harbor', 'ranks': ranks});
    });

    test('rejects a bad target', () {
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'Harbor', 'ranks': ranks}), throwsFormatException);
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'har bor', 'ranks': ranks}), throwsFormatException);
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': '', 'ranks': ranks}), throwsFormatException);
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'ranks': ranks}), throwsFormatException);
    });

    test('rejects a bad vocabulary size or missing ranks', () {
      expect(() => CompassPuzzle.parse({'vocabularySize': 0}, {'target': 'harbor', 'ranks': ranks}), throwsFormatException);
      expect(() => CompassPuzzle.parse({'vocabularySize': '10'}, {'target': 'harbor', 'ranks': ranks}), throwsFormatException);
      expect(() => CompassPuzzle.parse({}, {'target': 'harbor', 'ranks': ranks}), throwsFormatException);
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor'}), throwsFormatException);
      expect(() => CompassPuzzle.parse({'vocabularySize': 9}, {'target': 'harbor', 'ranks': ranks}), throwsFormatException);
    });

    test('rejects ranks that are not the integers 1..N once each', () {
      final duplicate = {...ranks, 'anchor': 1};
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': duplicate}), throwsFormatException);
      final tooHigh = {...ranks, 'anchor': 11};
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': tooHigh}), throwsFormatException);
      final zero = {...ranks, 'anchor': 0};
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': zero}), throwsFormatException);
      final notInt = {...ranks, 'anchor': '10'};
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': notInt}), throwsFormatException);
      final badKey = {...ranks}..remove('anchor');
      badKey['Anchor'] = 10;
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': badKey}), throwsFormatException);
    });

    test('rejects the target among the ranks', () {
      final withTarget = {...ranks}..remove('anchor');
      withTarget['harbor'] = 10;
      expect(() => CompassPuzzle.parse({'vocabularySize': 10}, {'target': 'harbor', 'ranks': withTarget}), throwsFormatException);
    });
  });

  group('normalisation and rankOf', () {
    test('lower-cases, trims and folds accents', () {
      expect(CompassPuzzle.normalise('  Port '), 'port');
      expect(CompassPuzzle.normalise('CAFÉ'), 'cafe');
      expect(CompassPuzzle.normalise('naïve'), 'naive');
      expect(CompassPuzzle.normalise('Straße'), 'strasse');
      expect(CompassPuzzle.normalise('œuvre'), 'oeuvre');
      expect(CompassPuzzle.isWord('port'), isTrue);
      expect(CompassPuzzle.isWord('two words'), isFalse);
      expect(CompassPuzzle.isWord("don't"), isFalse);
      expect(CompassPuzzle.isWord(''), isFalse);
    });

    test('rankOf finds ranked words after normalisation and null otherwise', () {
      expect(puzzle.rankOf('port'), 1);
      expect(puzzle.rankOf(' DOCK '), 2);
      expect(puzzle.rankOf('Ánchor'), 10);
      expect(puzzle.rankOf('banana'), isNull);
      expect(puzzle.rankOf('harbor'), isNull);
      expect(puzzle.isTarget(' Harbor'), isTrue);
      expect(puzzle.isTarget('port'), isFalse);
    });

    test('proximity bands scale with the vocabulary', () {
      final big = CompassPuzzle.parse(
        {'vocabularySize': 5000},
        {'target': 'zzzz', 'ranks': {for (var i = 1; i <= 5000; i++) syntheticWord(i): i}},
      );
      expect(big.proximityOf(1), Proximity.veryClose);
      expect(big.proximityOf(50), Proximity.veryClose);
      expect(big.proximityOf(51), Proximity.close);
      expect(big.proximityOf(500), Proximity.close);
      expect(big.proximityOf(501), Proximity.warm);
      expect(big.proximityOf(5000), Proximity.warm);
      expect(big.proximityOf(null), Proximity.far);
      expect(big.proximityFraction(1), 1.0);
      expect(big.proximityFraction(5000), closeTo(0, 0.001));
      expect(big.proximityFraction(null), 0.0);
      expect(big.proximityFraction(10), greaterThan(big.proximityFraction(100)));
    });
  });

  group('CompassState', () {
    test('records guesses in order with ranks and tracks the best', () {
      var state = CompassState.initial(puzzle);
      expect(state.bestRank, isNull);
      expect(state.hintRank, 5);
      state = state.submit('Boat');
      state = state.submit('banana');
      state = state.submit('port');
      expect(state.guesses.map((g) => g.word), ['boat', 'banana', 'port']);
      expect(state.guesses.map((g) => g.rank), [4, null, 1]);
      expect(state.sorted.map((g) => g.word), ['port', 'boat', 'banana']);
      expect(state.best!.word, 'port');
      expect(state.bestRank, 1);
      expect(state.attempts, 3);
      expect(state.solved, isFalse);
      expect(state.isOver, isFalse);
    });

    test('rejects repeats, non-words and guesses after the end', () {
      var state = CompassState.initial(puzzle).submit('port');
      expect(() => state.submit('PORT'), throwsArgumentError);
      expect(() => state.submit('two words'), throwsArgumentError);
      expect(state.contains(' Port'), isTrue);
      state = state.submit('harbor');
      expect(state.solved, isTrue);
      expect(() => state.submit('dock'), throwsStateError);
      expect(() => state.giveUp(), throwsStateError);
      expect(state.canHint, isFalse);
    });

    test('solves when the target is guessed and reports share lines', () {
      final state = CompassState.initial(puzzle).submit('dock').submit('sea').submit('harbor');
      expect(state.solved, isTrue);
      expect(state.bestRank, 0);
      expect(state.best!.isTarget, isTrue);
      expect(state.sorted.first.word, 'harbor');
      expect(state.attempts, 3);
      expect(state.shareLines(), ['🧭 solved in 3 guesses']);
      expect(state.summary(), 'Solved in 3 guesses');
      expect(CompassState.initial(puzzle).submit('harbor').shareLines(), ['🧭 solved in 1 guess']);
    });

    test('hint reveals the word at half the best rank and counts', () {
      var state = CompassState.initial(puzzle).submit('anchor');
      expect(state.bestRank, 10);
      expect(state.hintRank, 5);
      state = state.hint();
      expect(state.guesses.last, const CompassGuess(word: 'pier', rank: 5, isTarget: false, isHint: true));
      expect(state.hints, 1);
      expect(state.attempts, 1);
      expect(state.bestRank, 5);
      expect(state.hintRank, 2);
      state = state.submit('dock');
      expect(state.hintRank, 1);
      state = state.submit('port');
      expect(state.hintRank, isNull);
      expect(state.canHint, isFalse);
      expect(() => state.hint(), throwsStateError);
      expect(state.shareLines(), ['🧭 gave up after 3 guesses, closest #1 · 1 hint']);
    });

    test('hint with no ranked guess reveals the middle of the list', () {
      final state = CompassState.initial(puzzle).submit('banana').hint();
      expect(state.guesses.last.word, 'pier');
      expect(state.guesses.last.isHint, isTrue);
    });

    test('giving up ends the play unsolved', () {
      final state = CompassState.initial(puzzle).submit('dock').giveUp();
      expect(state.isOver, isTrue);
      expect(state.solved, isFalse);
      expect(state.gaveUp, isTrue);
      expect(state.canHint, isFalse);
      expect(state.shareLines(), ['🧭 gave up after 1 guess, closest #2']);
      expect(state.summary(), 'Not solved · 1 guess');
    });

    test('round-trips through JSON', () {
      final state = CompassState.initial(puzzle).submit('boat').hint().submit('banana').giveUp();
      final json = state.toJson();
      expect(json, {
        'guesses': [
          {'word': 'boat'},
          {'word': 'dock', 'hint': true},
          {'word': 'banana'},
        ],
        'gaveUp': true,
      });
      expect(CompassState.fromJson(puzzle, json), state);
      final solved = CompassState.initial(puzzle).submit('harbor');
      expect(CompassState.fromJson(puzzle, solved.toJson()), solved);
      expect(solved.toJson().containsKey('gaveUp'), isFalse);
    });

    test('rejects malformed progress', () {
      expect(() => CompassState.fromJson(puzzle, {}), throwsFormatException);
      expect(() => CompassState.fromJson(puzzle, {'guesses': 'port'}), throwsFormatException);
      expect(() => CompassState.fromJson(puzzle, {'guesses': ['port']}), throwsFormatException);
      expect(
        () => CompassState.fromJson(puzzle, {
          'guesses': [
            {'word': 'Port'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => CompassState.fromJson(puzzle, {
          'guesses': [
            {'word': 'port'},
            {'word': 'port'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => CompassState.fromJson(puzzle, {
          'guesses': [
            {'word': 'harbor'},
            {'word': 'port'},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => CompassState.fromJson(puzzle, {
          'guesses': [
            {'word': 'banana', 'hint': true},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => CompassState.fromJson(puzzle, {
          'guesses': [
            {'word': 'harbor'},
          ],
          'gaveUp': true,
        }),
        throwsFormatException,
      );
    });
  });
}
