import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/linked/linked.dart';

import 'fixtures.dart';

void main() {
  LinkedPuzzle parse({Map<String, dynamic>? payload, Map<String, dynamic>? reveal}) =>
      LinkedPuzzle.parse(payload ?? flagPayload(), reveal ?? flagReveal());

  Map<String, dynamic> payloadWith(void Function(Map<String, dynamic>) change) {
    final payload = flagPayload();
    change(payload);
    return payload;
  }

  Map<String, dynamic> revealWith(void Function(Map<String, dynamic>) change) {
    final reveal = flagReveal();
    change(reveal);
    return reveal;
  }

  List<dynamic> setsOf(Map<String, dynamic> payload) => payload['sets'] as List;

  group('parse', () {
    test('accepts a well-formed puzzle', () {
      final puzzle = parse();
      expect(puzzle.sets, hasLength(3));
      expect(puzzle.sets.map((s) => s.answer), ['Green', 'White', 'Orange']);
      expect(puzzle.sets.first.clues, hasLength(2));
      expect(puzzle.finalAnswer, 'The flag of Ireland');
      expect(puzzle.finalAliases, ['Irish flag']);
      expect(puzzle.explanations, hasLength(4));
      expect(puzzle.linkExplanation, puzzle.explanations.last);
      expect(puzzle.finalHint, startsWith('A vertical banner'));
    });

    test('round trips through toPayload and toReveal', () {
      final puzzle = parse();
      expect(LinkedPuzzle.parse(puzzle.toPayload(), puzzle.toReveal()), puzzle);
    });

    test('rejects the wrong number of sets, clues or explanations', () {
      expect(() => parse(payload: payloadWith((p) => setsOf(p).removeLast())), throwsFormatException);
      expect(() => parse(payload: {'sets': 'three'}), throwsFormatException);
      expect(
        () => parse(payload: payloadWith((p) => (setsOf(p)[0] as Map)['clues'] = ['only one clue here'])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('exactly 2 "clues"'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => (r['explanations'] as List).removeLast())),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('explanations'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => (r['answers'] as List).removeLast())),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('one per set'))),
      );
      expect(() => parse(reveal: revealWith((r) => r['aliases'] = [<String>[]])), throwsFormatException);
    });

    test('rejects a clue or a hint of the wrong shape or length', () {
      expect(
        () => parse(payload: payloadWith((p) => (setsOf(p)[1] as Map)['clues'] = <Object?>['too short', 7])),
        throwsFormatException,
      );
      expect(
        () => parse(payload: payloadWith((p) => ((setsOf(p)[1] as Map)['clues'] as List)[0] = 'short')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('5 characters'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => (setsOf(p)[1] as Map)['hint'] = 'x' * 121)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('hint'))),
      );
    });

    test('rejects two clues that say the same thing', () {
      expect(
        () => parse(payload: payloadWith((p) {
          final first = ((setsOf(p)[0] as Map)['clues'] as List)[0] as String;
          ((setsOf(p)[2] as Map)['clues'] as List)[1] = '$first!';
        })),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats an earlier clue'))),
      );
    });

    test('rejects an answer with no letters, or one that repeats another', () {
      expect(() => parse(reveal: revealWith((r) => (r['answers'] as List)[0] = '!!')), throwsFormatException);
      expect(
        () => parse(reveal: revealWith((r) => (r['answers'] as List)[2] = 'green')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats answer 1'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => (r['aliases'] as List)[1] = ['GREEN!'])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats answer 1'))),
      );
      expect(
        () => parse(reveal: revealWith((r) => r['finalAliases'] = ['the White'])),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats answer 2'))),
      );
    });

    test('rejects a missing final subject or a too-short explanation', () {
      expect(() => parse(reveal: revealWith((r) => r.remove('final'))), throwsFormatException);
      expect(() => parse(reveal: revealWith((r) => r['final'] = '  ')), throwsFormatException);
      expect(
        () => parse(reveal: revealWith((r) => (r['explanations'] as List)[3] = 'It is a flag.')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('too short'))),
      );
    });

    test('rejects a clue or hint that gives an answer or the final away', () {
      expect(
        () => parse(payload: payloadWith((p) => ((setsOf(p)[0] as Map)['clues'] as List)[0] = 'The green of a spring field')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('set 1 gives an answer away'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => ((setsOf(p)[1] as Map)['clues'] as List)[0] = 'One band of the Irish flag')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('set 2 gives an answer away'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => (setsOf(p)[2] as Map)['hint'] = 'Think of an orange in a bowl')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('set 3 gives an answer away'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => p['finalHint'] = 'The flag of Ireland has three bands')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('"finalHint" gives an answer away'))),
      );
      expect(
        () => parse(payload: payloadWith((p) => ((setsOf(p)[0] as Map)['clues'] as List)[1] = 'A band on the flag of Ireland')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('gives an answer away'))),
      );
    });

    test('works out a hint from the answer when the content gives none', () {
      final puzzle = parse(payload: payloadWith((p) {
        for (final set in setsOf(p)) {
          (set as Map).remove('hint');
        }
        p.remove('finalHint');
      }));
      expect(puzzle.sets[0].hint, 'Starts with G · 5 letters');
      expect(puzzle.sets[2].hint, 'Starts with O · 6 letters');
      expect(puzzle.finalHint, 'Starts with F · 4, 2 and 7 letters');
      expect(LinkedPuzzle.shapeHint('coral reef'), 'Starts with C · 5 and 4 letters');
      expect(() => LinkedPuzzle.shapeHint('!!'), throwsFormatException);
    });
  });

  group('matching', () {
    final puzzle = LinkedPuzzle.parse(flagPayload(), flagReveal());

    test('takes an answer however it is written, in its own set only', () {
      expect(puzzle.acceptsAt(0, 'Green'), isTrue);
      expect(puzzle.acceptsAt(0, '  green!  '), isTrue);
      expect(puzzle.acceptsAt(0, 'the green'), isTrue);
      expect(puzzle.acceptsAt(1, 'Green'), isFalse);
      expect(puzzle.acceptsAt(2, 'Orange Colour'), isTrue);
      expect(puzzle.acceptsAt(2, 'greens'), isFalse);
    });

    test('takes the final subject and its aliases', () {
      expect(puzzle.acceptsFinal('The flag of Ireland'), isTrue);
      expect(puzzle.acceptsFinal('flag of ireland'), isTrue);
      expect(puzzle.acceptsFinal('IRISH FLAG!'), isTrue);
      expect(puzzle.acceptsFinal('the flag of France'), isFalse);
      expect(puzzle.acceptsFinal(''), isFalse);
    });

    test('scoring constants match the contract', () {
      expect(LinkedPuzzle.maxPoints, 10);
      expect(LinkedPuzzle.minPointsWhenSolved, 1);
      expect(LinkedPuzzle.setCount, 3);
      expect(LinkedPuzzle.cluesPerSet, 2);
    });
  });
}
