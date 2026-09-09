import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/uncover/uncover.dart';

import 'fixtures.dart';

/// Builds a reveal from the fixture with [changes] applied, and a payload
/// whose text is the correctly masked version of it unless [maskedText] says
/// otherwise. Every rule of [UncoverPuzzle.parse] is exercised by handing it
/// one broken field at a time.
UncoverPuzzle parseWith({
  Map<String, Object?> changes = const {},
  Object? maskedText,
  Object? hints,
}) {
  final reveal = {...boatReveal(), ...changes};
  for (final entry in changes.entries) {
    if (entry.value == null) reveal.remove(entry.key);
  }
  final text = maskedText ?? UncoverPuzzle.maskedTextFor(reveal);
  return UncoverPuzzle.parse({'text': text, 'hints': ?hints}, reveal);
}

void main() {
  group('a valid puzzle', () {
    final puzzle = boatPuzzle();

    test('keeps the payload, the reveal and the classified words', () {
      expect(puzzle.subject, 'Paper Boat');
      expect(puzzle.aliases, ['paper ship']);
      expect(puzzle.answerWords, ['paper', 'boat']);
      expect(puzzle.hints, hasLength(3));
      expect(puzzle.text, boatText);
      expect(puzzle.maskedText, boatMaskedText);
      expect(puzzle.wordCount, 103);
      expect(puzzle.hiddenCount, 49);
      expect(puzzle.subjectCount, 7, reason: 'two names, one alias and one lone answer word');
      expect(puzzle.toPayload(), boatPayload());
      expect(puzzle.toReveal(), boatReveal());
    });

    test('renders back to the payload text', () {
      expect(UncoverPuzzle.render(puzzle.words), boatMaskedText);
      expect(puzzle.words.map((w) => w.text).join(), boatText);
    });

    test('accepts the subject by any sensible spelling', () {
      for (final answer in ['Paper Boat', 'paper boat', '  PAPER   BOAT  ', 'paper-boat', 'the paper boat', 'Paper Boats!', 'paper ships']) {
        expect(puzzle.isAnswer(answer), isTrue, reason: answer);
      }
      for (final wrong in ['paper', 'boat', 'paper boats and ships', '', 'canoe']) {
        expect(puzzle.isAnswer(wrong), isFalse, reason: wrong);
      }
    });

    test('counts occurrences among the guessable words only', () {
      expect(puzzle.occurrences('sheet'), 2);
      expect(puzzle.occurrences('fold'), 1, reason: 'folds loses its plural s');
      expect(puzzle.occurrences('folded'), 2, reason: 'folded is a word of its own');
      expect(puzzle.occurrences('hull'), 1);
      expect(puzzle.occurrences('the'), 0, reason: 'common words are not guessable');
      expect(puzzle.occurrences(''), 0);
    });

    test('never counts a word of the subject, so it cannot be opened letter by letter', () {
      expect(puzzle.occurrences('paper'), 0);
      expect(puzzle.occurrences('boat'), 0);
      expect(puzzle.occurrences('ship'), 0);
      for (final word in puzzle.words.where((w) => w.isSubject)) {
        expect(['paper', 'boat', 'ship'], contains(word.normalised));
      }
    });
  });

  group('parse rejects', () {
    test('a reveal text carrying the mask character', () {
      expect(() => parseWith(changes: {'text': 'The ▇▇▇ $boatText'}), throwsFormatException);
    });

    test('a payload text that is not the masked reveal', () {
      expect(() => parseWith(maskedText: boatText), throwsFormatException);
      expect(() => parseWith(maskedText: boatMaskedText.replaceFirst('▇▇▇ ▇▇▇', '▇▇▇')), throwsFormatException);
    });

    test('answer words that are not the subject words', () {
      expect(() => parseWith(changes: {'answerWords': ['paper']}), throwsFormatException);
      expect(() => parseWith(changes: {'answerWords': ['paper', 'boat', 'ship']}), throwsFormatException);
      expect(() => parseWith(changes: {'answerWords': ['paper', 'canoe']}), throwsFormatException);
      expect(() => parseWith(changes: {'answerWords': null}), throwsFormatException);
    });

    test('a subject with no letters or only common words', () {
      expect(() => parseWith(changes: {'subject': '!!!', 'answerWords': ['paper', 'boat']}), throwsFormatException);
      expect(() => parseWith(changes: {'subject': 'The One', 'answerWords': ['one']}), throwsFormatException);
      expect(() => parseWith(changes: {'subject': '  '}), throwsFormatException);
    });

    test('a subject that never appears in the text', () {
      expect(
        () => parseWith(changes: {'subject': 'Cardboard Canoe', 'answerWords': ['cardboard', 'canoe'], 'aliases': <String>[]}),
        throwsFormatException,
      );
    });

    test('a text that is too short or too long', () {
      const short = 'A paper boat is a toy folded from one flat sheet, and almost every child makes one sooner or later.';
      expect(() => parseWith(changes: {'text': short}), throwsFormatException);
      expect(() => parseWith(changes: {'text': '$boatText $boatText'}), throwsFormatException);
    });

    test('a text that leaves too little to guess', () {
      final thin = 'A paper boat is a toy. ${'It is on the water and it is not in the air and they are with us. ' * 6}';
      expect(() => parseWith(changes: {'text': thin}), throwsFormatException);
    });

    test('an alias with no letters or only common words', () {
      expect(() => parseWith(changes: {'aliases': ['!!!']}), throwsFormatException);
      expect(() => parseWith(changes: {'aliases': ['the one']}), throwsFormatException);
      expect(() => parseWith(changes: {'aliases': 'paper ship'}), throwsFormatException);
    });

    test('more than three hints', () {
      expect(() => parseWith(hints: ['One.', 'Two.', 'Three.', 'Four.']), throwsFormatException);
    });

    test('a hint that gives away an answer word', () {
      expect(() => parseWith(hints: ['It is made of paper.']), throwsFormatException);
      expect(() => parseWith(hints: ['A toy.', 'Think of a boat.']), throwsFormatException);
    });

    test('a hint that gives away the subject by an alias', () {
      expect(
        () => parseWith(changes: {'aliases': ['origami vessel']}, hints: ['A kind of origami vessel.']),
        throwsFormatException,
      );
    });

    test('a malformed payload', () {
      expect(() => UncoverPuzzle.parse(const {}, boatReveal()), throwsFormatException);
      expect(() => UncoverPuzzle.parse({'text': 7}, boatReveal()), throwsFormatException);
      expect(() => parseWith(hints: 'a hint'), throwsFormatException);
      expect(() => parseWith(hints: ['fine', 3]), throwsFormatException);
      expect(() => UncoverPuzzle.parse(boatPayload(), const {}), throwsFormatException);
    });
  });

  test('maskedTextFor prepares the payload text for an editor', () {
    expect(UncoverPuzzle.maskedTextFor(boatReveal()), boatMaskedText);
    expect(
      UncoverPuzzle.maskedTextFor({'text': 'A paper boat floats.', 'subject': 'Paper Boat'}),
      'A ▇▇▇ ▇▇▇ floats.',
    );
  });

  test('answerWordsFor keeps the subject words that are worth hiding', () {
    expect(UncoverPuzzle.answerWordsFor('Angel Falls'), ['angel', 'fall']);
    expect(UncoverPuzzle.answerWordsFor('The Great Wave off Kanagawa'), ['great', 'wave', 'kanagawa']);
    expect(UncoverPuzzle.answerWordsFor('Braille'), ['braille']);
    expect(() => UncoverPuzzle.answerWordsFor('the one'), throwsFormatException);
  });
}
