import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues.dart';

import 'fixtures.dart';

void main() {
  FiveCluesPuzzle parse({Map<String, dynamic>? payload, Map<String, dynamic>? reveal}) =>
      FiveCluesPuzzle.parse(payload ?? honeyPayload(), reveal ?? honeyReveal());

  Map<String, dynamic> payloadWith(void Function(Map<String, dynamic>) change) {
    final payload = honeyPayload();
    change(payload);
    return payload;
  }

  Map<String, dynamic> revealWith(void Function(Map<String, dynamic>) change) {
    final reveal = honeyReveal();
    change(reveal);
    return reveal;
  }

  group('parse', () {
    test('accepts a well-formed puzzle', () {
      final puzzle = parse();
      expect(puzzle.clues, hasLength(5));
      expect(puzzle.answer, 'Honey');
      expect(puzzle.aliases, ['runny honey']);
      expect(puzzle.explanations, hasLength(5));
      expect(puzzle.accepted, {'honey', 'runny honey'});
    });

    test('round trips through toPayload and toReveal', () {
      final puzzle = parse();
      expect(FiveCluesPuzzle.parse(puzzle.toPayload(), puzzle.toReveal()), puzzle);
    });

    test('rejects a clue list that is not exactly five clues', () {
      expect(() => parse(payload: payloadWith((p) => (p['clues'] as List).removeLast())), throwsFormatException);
      expect(() => parse(payload: payloadWith((p) => (p['clues'] as List).add('A sixth clue about bees'))), throwsFormatException);
      expect(() => parse(payload: {'clues': 'five'}), throwsFormatException);
      expect(() => parse(payload: {}), throwsFormatException);
    });

    test('rejects a clue that is not a non-empty string', () {
      expect(() => parse(payload: payloadWith((p) => (p['clues'] as List)[2] = 7)), throwsFormatException);
      expect(() => parse(payload: payloadWith((p) => (p['clues'] as List)[2] = '  ')), throwsFormatException);
    });

    test('rejects a clue that is too short or too long', () {
      expect(
        () => parse(payload: payloadWith((p) => (p['clues'] as List)[0] = 'Sticky')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('clue 1'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => (p['clues'] as List)[0] = 'x' * 121)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('121 characters'))),
      );
    });

    test('rejects two clues that say the same thing', () {
      expect(
        () => parse(payload: payloadWith((p) => (p['clues'] as List)[1] = '  ${(p['clues'] as List)[0]}!  ')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats'))),
      );
    });

    test('rejects a missing answer or one with no letters', () {
      expect(() => parse(reveal: revealWith((r) => r.remove('answer'))), throwsFormatException);
      expect(() => parse(reveal: revealWith((r) => r['answer'] = '   ')), throwsFormatException);
      expect(
        () => parse(reveal: revealWith((r) => r['answer'] = '!!!')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('no letters'))),
      );
    });

    test('rejects an alias that is empty, or repeats the answer or another alias', () {
      expect(() => parse(reveal: revealWith((r) => r['aliases'] = ['ok', ''])), throwsFormatException);
      expect(() => parse(reveal: revealWith((r) => r['aliases'] = 'honey')), throwsFormatException);
      expect(
        () => parse(reveal: revealWith((r) => r['aliases'] = ['the honey'])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats the answer'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => r['aliases'] = ['runny honey', 'Runny Honey!'])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats'))),
      );
    });

    test('rejects explanations that are missing, miscounted, too short or a copy of the clue', () {
      expect(() => parse(reveal: revealWith((r) => r.remove('explanations'))), throwsFormatException);
      expect(
        () => parse(reveal: revealWith((r) => (r['explanations'] as List).removeLast())),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('one per clue'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => (r['explanations'] as List)[3] = 'Bees do it.')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('too short'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => (r['explanations'] as List)[3] = honeyPayload()['clues'][3])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats its clue'))),
      );
    });

    test('rejects a clue that gives the answer away, by name or by alias', () {
      expect(
        () => parse(payload: payloadWith((p) => (p['clues'] as List)[2] = 'Bees make honey out of nectar')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('clue 3 gives the answer away'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => (p['clues'] as List)[4] = 'A jar of runny honey on the shelf')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('gives the answer away'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => (p['clues'] as List)[4] = 'The HONEY, sold in jars, is thick')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('gives the answer away'))),
      );
    });

    test('lets a clue use a word that merely contains the answer', () {
      final puzzle = parse(payload: payloadWith((p) => (p['clues'] as List)[0] = 'The honeydew of aphids is one source'));
      expect(puzzle.clues.first, contains('honeydew'));
    });
  });

  group('accepts', () {
    final puzzle = FiveCluesPuzzle.parse(honeyPayload(), honeyReveal());

    test('takes the answer however it is capitalised, spaced or punctuated', () {
      for (final guess in ['Honey', 'honey', '  HONEY  ', 'honey!', 'the honey', 'Ho ney'.replaceAll(' ', '')]) {
        expect(puzzle.accepts(guess), isTrue, reason: guess);
      }
    });

    test('takes an alias and refuses anything else', () {
      expect(puzzle.accepts('runny honey'), isTrue);
      expect(puzzle.accepts('Runny  Honey.'), isTrue);
      expect(puzzle.accepts('honeys'), isFalse);
      expect(puzzle.accepts('nectar'), isFalse);
      expect(puzzle.accepts(''), isFalse);
      expect(puzzle.accepts('   '), isFalse);
    });

    test('scores five points on the first clue down to one on the last', () {
      expect([for (var i = 0; i < 5; i++) FiveCluesPuzzle.pointsForClue(i)], [5, 4, 3, 2, 1]);
    });
  });

  group('FiveCluesText', () {
    test('lower-cases, folds accents and drops punctuation', () {
      expect(FiveCluesText.normalise('Café Crème!'), 'cafe creme');
      expect(FiveCluesText.normalise('  Ångström–Meter  '), 'angstrom meter');
      expect(FiveCluesText.normalise("the bee's knees"), 'bee knees');
      expect(FiveCluesText.normalise('coral-reef'), 'coral reef');
    });

    test('drops a leading article only when a word remains', () {
      expect(FiveCluesText.normalise('The Great Barrier Reef'), 'great barrier reef');
      expect(FiveCluesText.normalise('An owl'), 'owl');
      expect(FiveCluesText.normalise('The'), 'the');
    });

    test('does not stem, so a plural is a different answer', () {
      expect(FiveCluesText.normalise('owls'), 'owls');
      expect(FiveCluesText.normalise('cities'), 'cities');
    });

    test('containsPhrase matches whole words in order, not fragments', () {
      expect(FiveCluesText.containsPhrase('a jar of clear honey', 'honey'), isTrue);
      expect(FiveCluesText.containsPhrase('the honeydew of aphids', 'honey'), isFalse);
      expect(FiveCluesText.containsPhrase('built on a coral reef today', 'coral reef'), isTrue);
      expect(FiveCluesText.containsPhrase('coral and reef', 'coral reef'), isFalse);
      expect(FiveCluesText.containsPhrase('anything', ''), isFalse);
    });

    test('significantWords drops the small connecting words', () {
      expect(FiveCluesText.significantWords('the flag of Ireland'), ['flag', 'ireland']);
    });
  });
}
