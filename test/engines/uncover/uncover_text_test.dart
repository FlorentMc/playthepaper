import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/uncover/uncover_text.dart';

void main() {
  group('normaliseWord', () {
    test('lower-cases, folds accents and drops punctuation', () {
      expect(UncoverText.normaliseWord('Angel'), 'angel');
      expect(UncoverText.normaliseWord('Merú'), 'meru');
      expect(UncoverText.normaliseWord('façade'), 'facade');
      expect(UncoverText.normaliseWord('Körepakupai'), 'korepakupai');
      expect(UncoverText.normaliseWord('“quoted,”'), 'quoted');
      expect(UncoverText.normaliseWord('  Fjord!  '), 'fjord');
      expect(UncoverText.normaliseWord('1,864'), '1864');
      expect(UncoverText.normaliseWord('---'), '');
    });

    test('drops a possessive ending', () {
      expect(UncoverText.normaliseWord("river's"), 'river');
      expect(UncoverText.normaliseWord('river’s'), 'river');
      expect(UncoverText.normaliseWord("Leonardo's"), 'leonardo');
    });

    test('strips a plural ending only where it is safe', () {
      expect(UncoverText.normaliseWord('falls'), 'fall');
      expect(UncoverText.normaliseWord('cities'), 'city');
      expect(UncoverText.normaliseWord('branches'), 'branch');
      expect(UncoverText.normaliseWord('wishes'), 'wish');
      expect(UncoverText.normaliseWord('boxes'), 'box');
      expect(UncoverText.normaliseWord('ties'), 'tie');
      expect(UncoverText.normaliseWord('glass'), 'glass');
      expect(UncoverText.normaliseWord('bus'), 'bus');
      expect(UncoverText.normaliseWord('gas'), 'gas');
      expect(UncoverText.normaliseWord('ship'), UncoverText.normaliseWord('ships'));
    });
  });

  group('normalisePhrase', () {
    test('normalises each word, drops a leading article and joins with one space', () {
      expect(UncoverText.normalisePhrase('The Angel Falls'), 'angel fall');
      expect(UncoverText.normalisePhrase('  angel   falls  '), 'angel fall');
      expect(UncoverText.normalisePhrase('Angel-Falls'), 'angel fall');
      expect(UncoverText.normalisePhrase('Salto Ángel!'), 'salto angel');
      expect(UncoverText.normalisePhrase('the'), 'the', reason: 'a lone article is left alone');
      expect(UncoverText.normalisePhrase('   '), '');
    });
  });

  test('common words are shown from the start', () {
    expect(UncoverText.isCommon('the'), isTrue);
    expect(UncoverText.isCommon('of'), isTrue);
    expect(UncoverText.isCommon(UncoverText.normaliseWord('They')), isTrue);
    expect(UncoverText.isCommon('waterfall'), isFalse);
    expect(UncoverText.isCommon(''), isFalse);
  });

  group('tokenise', () {
    test('every character lands in exactly one token', () {
      const text = 'The Auyán-tepui, 979 metres tall — a “tepui”. It drops 807 m.';
      final tokens = UncoverText.tokenise(text);
      expect(tokens.map((t) => t.text).join(), text);
      expect(tokens.where((t) => t.isWord).map((t) => t.text), contains('Auyán'));
      expect(tokens.where((t) => t.isWord).map((t) => t.normalised), contains('979'));
    });

    test('a mask run is one token of its own', () {
      final tokens = UncoverText.tokenise('The ▇▇▇ ▇▇▇ is tall.');
      expect(tokens.where((t) => t.kind == UncoverTokenKind.mask), hasLength(2));
      expect(tokens.where((t) => t.isWord).map((t) => t.normalised), ['the', 'is', 'tall']);
    });
  });

  test('phrase words are joined by spacing or a hyphen only', () {
    expect(UncoverText.joinsPhrase(' '), isTrue);
    expect(UncoverText.joinsPhrase('-'), isTrue);
    expect(UncoverText.joinsPhrase(' — '), isTrue);
    expect(UncoverText.joinsPhrase(', '), isFalse);
    expect(UncoverText.joinsPhrase('. '), isFalse);
  });
}
