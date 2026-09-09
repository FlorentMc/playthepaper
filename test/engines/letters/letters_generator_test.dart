import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/engines/letters/letters.dart';
import 'package:test/test.dart';

void main() {
  final date = DateTime.utc(2026, 9, 8);

  /// Four-letter words made of [first] and three other letters of BRACHET.
  List<String> wordsWith(String first, String others) => [
    for (var i = 0; i < others.length; i++)
      for (var j = i + 1; j < others.length; j++)
        for (var k = j + 1; k < others.length; k++) '$first${others[i]}${others[j]}${others[k]}',
  ];

  /// Two pangrams, BRACHET, whose set qualifies, and JUMPING, whose set never
  /// can, plus twenty words with T so that only T qualifies as the centre;
  /// [twoCentres] adds ten words with A so that A qualifies as well.
  LettersGenerator generator({bool twoCentres = false}) {
    final words = ['brachet', 'jumping', ...wordsWith('t', 'abcehr'), if (twoCentres) ...wordsWith('a', 'bcehr')];
    return LettersGenerator(
      pool: LettersGenerator.buildPool(enable: words.toSet(), rankedWords: words),
    );
  }

  const seed = LettersSeed(
    pangram: 'BRACHET',
    storyId: 'hunt-1-hound',
    teaser: "Today's letters come from a story about a hunting hound.",
    excerpt: 'A brachet, the old word for a scent hound, ran ahead of the riders.',
  );

  group('buildPool', () {
    test('keeps ranked, lowercase, listed words of four letters or more', () {
      final pool = LettersGenerator.buildPool(
        enable: {'beat', 'teach', 'damn', 'tea', 'ghost', 'abc'},
        rankedWords: ['beat', 'Tea', 'damn', 'teach', 'ghost', 'beat', 'unlisted', 'abc'],
      );
      expect(pool.map((p) => p.word), ['beat', 'teach', 'ghost']);
      expect(pool.map((p) => p.rank), [1, 4, 5]);
    });

    test('only the first ranks count', () {
      final words = [for (var i = 0; i < LettersGenerator.poolMaxRank + 5; i++) _synthetic(i)];
      final pool = LettersGenerator.buildPool(enable: {_synthetic(49999), _synthetic(50000)}, rankedWords: words);
      expect(pool.map((p) => p.word), [_synthetic(49999)]);
      expect(pool.single.rank, 50000);
    });
  });

  group('unseeded generation', () {
    test('is deterministic and carries only the classic fields', () {
      final a = generator().generate(date);
      final b = generator().generate(date);
      expect(a, isNotNull);
      expect(a, b);
      expect(a!.id.toString(), 'letters-2026-09-08-en-v1');
      expect(a.dictionaryVersion, LettersGenerator.dictionaryVersion);
      expect(a.payload, {'center': 'T', 'outer': 'ABCEHR', 'minLength': 4});
      expect(a.reveal.keys, ['answers', 'pangrams', 'maxScore']);
      expect(a.reveal['pangrams'], ['BRACHET']);
      expect(a.reveal['answers'], hasLength(21));
      expect(a.storyId, isNull);
      expect(a.toJson().containsKey('storyId'), isFalse);
    });

    test('never reuses a letter set', () {
      final g = generator();
      expect(g.generate(date), isNotNull);
      expect(g.usedSets, {LettersGenerator.maskOf('brachet')});
      expect(g.generate(date.add(const Duration(days: 1))), isNull);

      final h = generator()..markUsed({'A', 'B', 'C', 'E', 'H', 'R', 'T'});
      expect(h.generate(date), isNull);
    });

    test('matches the published file when built from the shipped word lists', () {
      final g = _shippedGenerator();
      final text = '${const JsonEncoder.withIndent('  ').convert(g.generate(date)!.toJson())}\n';
      expect(text, File('test/fixtures/unseeded/letters-2026-09-08-en-v1.json').readAsStringSync());
    });
  });

  group('seeded generation', () {
    test('uses the story pangram and adds the story fields', () {
      final record = generator().generate(date, seed: seed);
      expect(record, isNotNull);
      expect(record!.storyId, 'hunt-1-hound');
      expect(record.payload, {'center': 'T', 'outer': 'ABCEHR', 'minLength': 4, 'teaser': seed.teaser});
      expect(record.reveal.keys, ['answers', 'pangrams', 'maxScore', 'storyId', 'excerpt']);
      expect(record.reveal['pangrams'], contains('BRACHET'));
      expect(record.reveal['storyId'], 'hunt-1-hound');
      expect(record.reveal['excerpt'], seed.excerpt);
      expect(record.toJson()['storyId'], 'hunt-1-hound');
      final puzzle = LettersPuzzle.parse(record.payload, record.reveal);
      expect(puzzle.pangrams, ['BRACHET']);
    });

    test('is deterministic for a date', () {
      final a = generator().generate(date, seed: seed);
      final b = generator().generate(date, seed: seed);
      expect(a, b);
    });

    test('tries the centres in a per-date order and takes the first that qualifies', () {
      final g = generator(twoCentres: true);
      final centres = <String>{};
      for (var d = 0; d < 14; d++) {
        final record = g.generate(date.add(Duration(days: d)), seed: seed);
        expect(record, isNotNull);
        final puzzle = LettersPuzzle.parse(record!.payload, record.reveal);
        expect(puzzle.letters, {'B', 'R', 'A', 'C', 'H', 'E', 'T'});
        expect(puzzle.pangrams, ['BRACHET']);
        expect(puzzle.answers.length, inInclusiveRange(LettersGenerator.minAnswers, LettersGenerator.maxAnswers));
        centres.add(puzzle.center);
      }
      expect(centres, {'T', 'A'});
      expect(g.generate(date, seed: seed)!.payload, g.generate(date, seed: seed)!.payload);
    });

    test('keeps the letter set of a shipped pangram', () {
      final g = _shippedGenerator();
      const bearing = LettersSeed(pangram: 'BEARING', storyId: 's', teaser: 't', excerpt: 'Bearing north.');
      final record = g.generate(date, seed: bearing);
      expect(record, isNotNull);
      final puzzle = LettersPuzzle.parse(record!.payload, record.reveal);
      expect(puzzle.center, 'B');
      expect(puzzle.outer, 'AEGINR');
      expect(puzzle.pangrams, contains('BEARING'));
      final shipped = jsonDecode(File('test/fixtures/unseeded/letters-2026-09-08-en-v1.json').readAsStringSync());
      expect(record.reveal['answers'], shipped['reveal']['answers']);
      expect(record.reveal['maxScore'], shipped['reveal']['maxScore']);
    });

    test('returns null when no centre of the pangram qualifies', () {
      const jumping = LettersSeed(pangram: 'JUMPING', storyId: 's', teaser: 't', excerpt: 'Jumping for joy.');
      final g = generator();
      expect(g.generate(date, seed: jumping), isNull);
      expect(g.usedSets, isEmpty);
    });

    test('rejects a pangram that is not uppercase, too short or not seven distinct letters', () {
      for (final bad in ['brachet', 'Brachet', 'BRACHE', 'BREATH', 'BRACHETS', 'BRA CHET', '']) {
        expect(
          () => generator().generate(
            date,
            seed: LettersSeed(pangram: bad, storyId: 's', teaser: 't', excerpt: '$bad.'),
          ),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('rejects a pangram outside the pool', () {
      expect(
        () => generator().generate(
          date,
          seed: const LettersSeed(pangram: 'BLACKED', storyId: 's', teaser: 't', excerpt: 'blacked out'),
        ),
        throwsFormatException,
      );
    });

    test('rejects an excerpt that lacks the pangram as a whole word', () {
      for (final excerpt in ['A brachets bark.', 'The subrachet.', 'Nothing here.', '']) {
        expect(
          () => generator().generate(
            date,
            seed: LettersSeed(pangram: 'BRACHET', storyId: 's', teaser: 't', excerpt: excerpt),
          ),
          throwsFormatException,
          reason: excerpt,
        );
      }
      final record = generator().generate(
        date,
        seed: const LettersSeed(pangram: 'BRACHET', storyId: 's', teaser: 't', excerpt: '"Brachet!" she called.'),
      );
      expect(record, isNotNull);
    });

    test('rejects an empty story id or teaser', () {
      expect(
        () => generator().generate(
          date,
          seed: const LettersSeed(pangram: 'BRACHET', storyId: '', teaser: 't', excerpt: 'brachet'),
        ),
        throwsFormatException,
      );
      expect(
        () => generator().generate(
          date,
          seed: const LettersSeed(pangram: 'BRACHET', storyId: 's', teaser: '', excerpt: 'brachet'),
        ),
        throwsFormatException,
      );
    });
  });

  group('pangramCandidatesIn', () {
    test('lists pool words with seven distinct letters in order, once each, uppercase', () {
      final g = generator();
      expect(
        g.pangramCandidatesIn('Jumping past the brachet; a Brachet, then jumping again. Teach, breath, blacked.'),
        ['JUMPING', 'BRACHET'],
      );
      expect(g.pangramCandidatesIn(''), isEmpty);
    });
  });

  test('maskOf and bitCount ignore case', () {
    expect(LettersGenerator.maskOf('BRACHET'), LettersGenerator.maskOf('brachet'));
    expect(LettersGenerator.bitCount(LettersGenerator.maskOf('brachet')), 7);
    expect(LettersGenerator.bitCount(LettersGenerator.maskOf('breath')), 6);
  });
}

String _synthetic(int i) {
  final tail = StringBuffer();
  var n = i;
  for (var k = 0; k < 4; k++) {
    tail.writeCharCode(97 + n % 26);
    n ~/= 26;
  }
  return 'w$tail';
}

LettersGenerator _shippedGenerator() {
  final enable = File('tool/data/enable1.txt').readAsLinesSync().map((l) => l.trim()).toSet();
  final rankedWords = File(
    'tool/data/en_50k.txt',
  ).readAsLinesSync().map((l) => l.trim().split(RegExp(r'\s+')).first).toList();
  return LettersGenerator(
    pool: LettersGenerator.buildPool(enable: enable, rankedWords: rankedWords),
  );
}
