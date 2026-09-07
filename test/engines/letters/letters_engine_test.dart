import 'package:daypencil/engines/letters/letters.dart';
import 'package:test/test.dart';

Map<String, dynamic> payload({String center = 'T', String outer = 'ABCEHR', int minLength = 4}) => {
  'center': center,
  'outer': outer,
  'minLength': minLength,
};

Map<String, dynamic> reveal({
  List<String> answers = const ['BEAT', 'BRACHET', 'BREATH', 'TEACH'],
  List<String> pangrams = const ['BRACHET'],
  int maxScore = 26,
}) => {'answers': answers, 'pangrams': pangrams, 'maxScore': maxScore};

LettersPuzzle puzzle() => LettersPuzzle.parse(payload(), reveal());

void main() {
  final letters = {'T', 'A', 'B', 'C', 'E', 'H', 'R'};

  group('scoring', () {
    test('four-letter words score one point', () {
      expect(scoreWord('BEAT', letters: letters), 1);
    });

    test('longer words score their length', () {
      expect(scoreWord('TEACH', letters: letters), 5);
      expect(scoreWord('BREATH', letters: letters), 6);
    });

    test('a seven-letter pangram scores fourteen', () {
      expect(isPangram('BRACHET', letters: letters), isTrue);
      expect(isPangram('BREATH', letters: letters), isFalse);
      expect(scoreWord('BRACHET', letters: letters), 14);
    });

    test('a longer pangram scores its length plus seven', () {
      expect(scoreWord('BRACHETT', letters: letters), 15);
    });
  });

  group('ranks', () {
    test('thresholds round up', () {
      expect(LettersRank.beginner.threshold(100), 0);
      expect(LettersRank.goodStart.threshold(100), 2);
      expect(LettersRank.goodStart.threshold(26), 1);
      expect(LettersRank.movingUp.threshold(26), 2);
      expect(LettersRank.good.threshold(26), 3);
      expect(LettersRank.solid.threshold(26), 4);
      expect(LettersRank.nice.threshold(26), 7);
      expect(LettersRank.great.threshold(26), 11);
      expect(LettersRank.amazing.threshold(26), 13);
      expect(LettersRank.genius.threshold(26), 19);
      expect(LettersRank.genius.threshold(50), 35);
      expect(LettersRank.genius.threshold(51), 36);
    });

    test('rankFor at boundaries', () {
      expect(LettersRank.rankFor(0, 100), LettersRank.beginner);
      expect(LettersRank.rankFor(1, 100), LettersRank.beginner);
      expect(LettersRank.rankFor(2, 100), LettersRank.goodStart);
      expect(LettersRank.rankFor(4, 100), LettersRank.goodStart);
      expect(LettersRank.rankFor(5, 100), LettersRank.movingUp);
      expect(LettersRank.rankFor(8, 100), LettersRank.good);
      expect(LettersRank.rankFor(14, 100), LettersRank.good);
      expect(LettersRank.rankFor(15, 100), LettersRank.solid);
      expect(LettersRank.rankFor(25, 100), LettersRank.nice);
      expect(LettersRank.rankFor(40, 100), LettersRank.great);
      expect(LettersRank.rankFor(49, 100), LettersRank.great);
      expect(LettersRank.rankFor(50, 100), LettersRank.amazing);
      expect(LettersRank.rankFor(69, 100), LettersRank.amazing);
      expect(LettersRank.rankFor(70, 100), LettersRank.genius);
      expect(LettersRank.rankFor(100, 100), LettersRank.genius);
    });

    test('rankFor uses rounded-up thresholds on odd maxima', () {
      expect(LettersRank.rankFor(18, 26), LettersRank.amazing);
      expect(LettersRank.rankFor(19, 26), LettersRank.genius);
      expect(LettersRank.rankFor(0, 26), LettersRank.beginner);
      expect(LettersRank.rankFor(1, 26), LettersRank.goodStart);
    });

    test('ranks are ordered with a next rank', () {
      expect(LettersRank.values.length, 9);
      expect(LettersRank.beginner.next, LettersRank.goodStart);
      expect(LettersRank.genius.next, isNull);
      expect(LettersRank.values.last, LettersRank.genius);
    });
  });

  group('puzzle parsing', () {
    test('parses a valid puzzle', () {
      final p = puzzle();
      expect(p.center, 'T');
      expect(p.outer, 'ABCEHR');
      expect(p.letters, letters);
      expect(p.answers, ['BEAT', 'BRACHET', 'BREATH', 'TEACH']);
      expect(p.pangrams, ['BRACHET']);
      expect(p.maxScore, 26);
      expect(p.contains('TEACH'), isTrue);
      expect(p.contains('CHEAT'), isFalse);
    });

    test('rejects the centre letter in the outer letters', () {
      expect(() => LettersPuzzle.parse(payload(outer: 'TBCEHR'), reveal()), throwsFormatException);
    });

    test('rejects repeated or lowercase letters', () {
      expect(() => LettersPuzzle.parse(payload(outer: 'AACEHR'), reveal()), throwsFormatException);
      expect(() => LettersPuzzle.parse(payload(center: 't'), reveal()), throwsFormatException);
      expect(() => LettersPuzzle.parse(payload(outer: 'abcehr'), reveal()), throwsFormatException);
      expect(() => LettersPuzzle.parse(payload(outer: 'ABCEH'), reveal()), throwsFormatException);
    });

    test('rejects an answer missing the centre letter', () {
      expect(
        () => LettersPuzzle.parse(
          payload(),
          reveal(answers: ['BEAT', 'BRACHET', 'BREATH', 'TEACH', 'BEACH'], maxScore: 31),
        ),
        throwsFormatException,
      );
    });

    test('rejects an answer with letters outside the puzzle', () {
      expect(
        () => LettersPuzzle.parse(
          payload(),
          reveal(answers: ['BEAT', 'BRACHET', 'BREATH', 'TEACH', 'TRACK'], maxScore: 31),
        ),
        throwsFormatException,
      );
    });

    test('rejects a short, lowercase or duplicate answer', () {
      expect(
        () => LettersPuzzle.parse(payload(), reveal(answers: ['BAT', 'BRACHET'], maxScore: 15)),
        throwsFormatException,
      );
      expect(
        () => LettersPuzzle.parse(payload(), reveal(answers: ['beat', 'BRACHET'], maxScore: 15)),
        throwsFormatException,
      );
      expect(
        () => LettersPuzzle.parse(payload(), reveal(answers: ['BEAT', 'BEAT', 'BRACHET'], maxScore: 16)),
        throwsFormatException,
      );
    });

    test('rejects a wrong maxScore', () {
      expect(() => LettersPuzzle.parse(payload(), reveal(maxScore: 25)), throwsFormatException);
      expect(() => LettersPuzzle.parse(payload(), reveal(maxScore: 27)), throwsFormatException);
    });

    test('rejects a pangram that is not listed', () {
      expect(() => LettersPuzzle.parse(payload(), reveal(pangrams: [])), throwsFormatException);
    });

    test('rejects a listed pangram that is not one, or not an answer', () {
      expect(() => LettersPuzzle.parse(payload(), reveal(pangrams: ['BRACHET', 'BREATH'])), throwsFormatException);
      expect(() => LettersPuzzle.parse(payload(), reveal(pangrams: ['BRACHET', 'CHARTEB'])), throwsFormatException);
    });

    test('rejects missing fields and empty answers', () {
      expect(() => LettersPuzzle.parse({'center': 'T', 'outer': 'ABCEHR'}, reveal()), throwsFormatException);
      expect(
        () => LettersPuzzle.parse(payload(), {'answers': [], 'pangrams': [], 'maxScore': 0}),
        throwsFormatException,
      );
      expect(
        () => LettersPuzzle.parse(payload(), {
          'answers': ['BEAT'],
          'maxScore': 1,
        }),
        throwsFormatException,
      );
    });
  });

  group('state', () {
    test('starts empty', () {
      final s = LettersState(puzzle: puzzle());
      expect(s.found, isEmpty);
      expect(s.points, 0);
      expect(s.rank, LettersRank.beginner);
      expect(s.isFinished, isFalse);
    });

    test('rejects a short word', () {
      expect(LettersState(puzzle: puzzle()).submit('BAT'), isA<SubmitTooShort>());
      expect(LettersState(puzzle: puzzle()).submit(''), isA<SubmitTooShort>());
    });

    test('rejects a word without the centre letter', () {
      expect(LettersState(puzzle: puzzle()).submit('BEACH'), isA<SubmitMissingCenter>());
    });

    test('rejects a word with letters outside the puzzle', () {
      expect(LettersState(puzzle: puzzle()).submit('TRACK'), isA<SubmitBadLetters>());
    });

    test('rejects a word not in the list', () {
      expect(LettersState(puzzle: puzzle()).submit('CHEAT'), isA<SubmitNotInList>());
    });

    test('accepts words, scores them and reports pangrams', () {
      final s0 = LettersState(puzzle: puzzle());
      final a = s0.submit('beat') as SubmitAccepted;
      expect(a.word, 'BEAT');
      expect(a.points, 1);
      expect(a.isPangram, isFalse);
      expect(a.state.found, ['BEAT']);
      expect(a.state.points, 1);
      expect(s0.found, isEmpty, reason: 'states are immutable');

      final b = a.state.submit('BRACHET') as SubmitAccepted;
      expect(b.points, 14);
      expect(b.isPangram, isTrue);
      expect(b.state.found, ['BEAT', 'BRACHET']);
      expect(b.state.points, 15);
      expect(b.state.pangramsFound, 1);
      expect(b.state.rank, LettersRank.amazing);
    });

    test('rejects a word already found', () {
      final a = LettersState(puzzle: puzzle()).submit('BEAT') as SubmitAccepted;
      expect(a.state.submit('BEAT'), isA<SubmitAlreadyFound>());
    });

    test('round-trips through json', () {
      final a = LettersState(puzzle: puzzle()).submit('TEACH') as SubmitAccepted;
      final b = a.state.submit('BEAT') as SubmitAccepted;
      final json = b.state.toJson();
      expect(json, {
        'found': ['TEACH', 'BEAT'],
        'finished': false,
      });
      final restored = LettersState.fromJson(puzzle(), json);
      expect(restored.found, ['TEACH', 'BEAT']);
      expect(restored.points, 6);
      expect(restored.isFinished, isFalse);
      expect(restored.foundSorted, ['BEAT', 'TEACH']);
    });

    test('drops unknown or repeated words when restoring', () {
      final restored = LettersState.fromJson(puzzle(), {
        'found': ['TEACH', 'CHEAT', 'TEACH', 7],
      });
      expect(restored.found, ['TEACH']);
    });

    test('finish locks the state', () {
      final a = LettersState(puzzle: puzzle()).submit('BEAT') as SubmitAccepted;
      final done = a.state.finish();
      expect(done.isFinished, isTrue);
      expect(done.found, ['BEAT']);
      expect(done.points, 1);
      expect(done.toJson()['finished'], isTrue);
      expect(LettersState.fromJson(puzzle(), done.toJson()).isFinished, isTrue);
      expect(() => done.submit('TEACH'), throwsStateError);
    });

    test('genius means solved', () {
      var s = LettersState(puzzle: puzzle());
      for (final w in ['BEAT', 'BRACHET', 'TEACH']) {
        s = (s.submit(w) as SubmitAccepted).state;
      }
      expect(s.points, 20);
      expect(s.rank, LettersRank.genius);
      expect(s.isComplete, isFalse);
      s = (s.submit('BREATH') as SubmitAccepted).state;
      expect(s.isComplete, isTrue);
      expect(s.points, 26);
    });
  });
}
