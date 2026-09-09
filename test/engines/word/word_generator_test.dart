import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/engines/word/word_engine.dart';
import 'package:test/test.dart';

void main() {
  final date = DateTime.utc(2026, 9, 8);
  const candidates = ['abduct', 'stream', 'whales', 'zombie'];
  const guessList = {'ABDUCT', 'STREAM', 'WHALES', 'ZOMBIE', 'STRAND', 'REOPEN'};
  const seed = WordSeed(
    answer: 'WHALES',
    storyId: 'nature-1-whale',
    teaser: 'Today\'s word comes from a story about the deep sea.',
    excerpt: 'Blue whales, the largest animals ever known, dive for up to half an hour.',
  );

  WordGenerator generator() => WordGenerator(candidates: candidates, guessList: guessList);

  /// Six hundred synthetic six-letter words that pass every filter.
  Set<String> filler() => {for (var i = 0; i < 600; i++) _filler(i)};

  group('buildCandidates', () {
    test('keeps common six-letter words and drops the rest', () {
      final enable = {
        ...filler(),
        'stream',
        'streams',
        'shouts',
        'shout',
        'walked',
        'walk',
        'hopped',
        'hop',
        'boxing',
        'box',
        'buried',
        'bury',
        'wishes',
        'wish',
        'nigger',
        'seldom',
        'zzzzzz',
      };
      final rankOf = {for (final w in enable) w: 100};
      rankOf['seldom'] = WordGenerator.preferredRank + 1;
      rankOf.remove('zzzzzz');
      final result = WordGenerator.buildCandidates(enable: enable, rankOf: rankOf);
      expect(result, contains('stream'));
      expect(result, isNot(contains('streams')));
      expect(result, isNot(contains('shouts')));
      expect(result, isNot(contains('walked')));
      expect(result, isNot(contains('hopped')));
      expect(result, isNot(contains('boxing')));
      expect(result, isNot(contains('buried')));
      expect(result, isNot(contains('wishes')));
      expect(result, isNot(contains('nigger')));
      expect(result, isNot(contains('seldom')));
      expect(result, isNot(contains('zzzzzz')));
      expect(result, List.of(result)..sort());
    });

    test('relaxes the rank when the preferred one yields too few', () {
      final words = filler().toList();
      final rankOf = <String, int>{};
      for (var i = 0; i < words.length; i++) {
        rankOf[words[i]] = i < 500 ? 100 : WordGenerator.preferredRank + 1;
      }
      rankOf['stream'] = 100;
      final enable = {...words, 'stream'};
      expect(WordGenerator.buildCandidates(enable: enable, rankOf: rankOf), hasLength(601));
    });

    test('throws when too few candidates remain after relaxing', () {
      final enable = {'stream', 'whales'};
      final rankOf = {'stream': 1, 'whales': 2};
      expect(() => WordGenerator.buildCandidates(enable: enable, rankOf: rankOf), throwsStateError);
    });
  });

  group('unseeded generation', () {
    test('is deterministic and carries only the classic fields', () {
      final a = generator().generate(date);
      final b = generator().generate(date);
      expect(a, b);
      expect(a.id.toString(), 'word-2026-09-08-en-v1');
      expect(a.dictionaryVersion, WordGenerator.dictionaryVersion);
      expect(a.payload.keys, ['length', 'firstLetter', 'maxGuesses']);
      expect(a.reveal.keys, ['answer']);
      expect(a.storyId, isNull);
      final answer = a.reveal['answer'] as String;
      expect(candidates, contains(answer.toLowerCase()));
      expect(a.payload['firstLetter'], answer[0]);
      expect(a.toJson().containsKey('storyId'), isFalse);
    });

    test('walks the schedule day by day', () {
      final g = generator();
      final answers = [for (var d = 0; d < candidates.length; d++) g.answerFor(date.add(Duration(days: d)))];
      expect(answers.toSet(), hasLength(candidates.length));
      expect(g.answerFor(date.add(Duration(days: candidates.length))), answers.first);
    });

    test('refuses an answer missing from the guess list', () {
      final g = WordGenerator(candidates: const ['bricks'], guessList: guessList);
      expect(() => g.generate(date), throwsStateError);
    });

    test('matches the published file when built from the shipped word lists', () {
      final enable = _readWords('tool/data/enable1.txt');
      final guesses = _readWords('assets/dictionaries/words6_en.txt', uppercase: true);
      final ranks = <String, int>{};
      var rank = 0;
      for (final line in File('tool/data/en_50k.txt').readAsLinesSync()) {
        final word = line.trim().split(RegExp(r'\s+')).first.toLowerCase();
        if (word.isEmpty) continue;
        rank++;
        ranks.putIfAbsent(word, () => rank);
      }
      final g = WordGenerator(
        candidates: WordGenerator.buildCandidates(enable: enable, rankOf: ranks),
        guessList: guesses,
      );
      final text = '${const JsonEncoder.withIndent('  ').convert(g.generate(date).toJson())}\n';
      expect(text, File('test/fixtures/unseeded/word-2026-09-08-en-v1.json').readAsStringSync());
    });
  });

  group('seeded generation', () {
    test('uses the story answer and adds the story fields', () {
      final record = generator().generate(date, seed: seed);
      expect(record.storyId, 'nature-1-whale');
      expect(record.payload, {'length': 6, 'firstLetter': 'W', 'maxGuesses': 6, 'teaser': seed.teaser});
      expect(record.reveal, {'answer': 'WHALES', 'storyId': 'nature-1-whale', 'excerpt': seed.excerpt});
      expect(record.toJson()['storyId'], 'nature-1-whale');
      expect(WordPuzzle.parse(record.payload, record.reveal).answer, 'WHALES');
    });

    test('is deterministic and independent of the schedule', () {
      final a = generator().generate(date, seed: seed);
      final b = generator().generate(date.add(const Duration(days: 3)), seed: seed);
      expect(a.payload, b.payload);
      expect(a.reveal, b.reveal);
    });

    test('accepts an answer that is not a scheduled candidate', () {
      final record = generator().generate(
        date,
        seed: const WordSeed(answer: 'REOPEN', storyId: 's', teaser: 't', excerpt: 'They will reopen the bridge.'),
      );
      expect(record.reveal['answer'], 'REOPEN');
    });

    test('rejects an answer that is not six uppercase letters', () {
      for (final bad in ['whales', 'WHALE', 'WHALESS', 'WHAL3S', '']) {
        expect(
          () => generator().generate(
            date,
            seed: WordSeed(answer: bad, storyId: 's', teaser: 't', excerpt: '$bad here'),
          ),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('rejects an answer outside the guess list', () {
      expect(
        () => generator().generate(
          date,
          seed: const WordSeed(answer: 'QQQQQQ', storyId: 's', teaser: 't', excerpt: 'qqqqqq'),
        ),
        throwsFormatException,
      );
    });

    test('rejects an excerpt that lacks the answer as a whole word', () {
      for (final excerpt in ['The whale dived.', 'The whaleship sailed.', 'Nothing here.', '']) {
        expect(
          () => generator().generate(
            date,
            seed: WordSeed(answer: 'WHALES', storyId: 's', teaser: 't', excerpt: excerpt),
          ),
          throwsFormatException,
          reason: excerpt,
        );
      }
    });

    test('matches the answer in the excerpt regardless of case and punctuation', () {
      for (final excerpt in ['Whales!', '(whales)', 'the WHALES\' song', 'two whales.']) {
        final record = generator().generate(
          date,
          seed: WordSeed(answer: 'WHALES', storyId: 's', teaser: 't', excerpt: excerpt),
        );
        expect(record.reveal['excerpt'], excerpt);
      }
    });

    test('rejects an empty story id or teaser', () {
      expect(
        () => generator().generate(
          date,
          seed: const WordSeed(answer: 'WHALES', storyId: '', teaser: 't', excerpt: 'whales'),
        ),
        throwsFormatException,
      );
      expect(
        () => generator().generate(
          date,
          seed: const WordSeed(answer: 'WHALES', storyId: 's', teaser: '', excerpt: 'whales'),
        ),
        throwsFormatException,
      );
    });
  });

  group('candidatesIn', () {
    test('lists candidate words of the text in order, once each, uppercase', () {
      final g = generator();
      expect(g.candidatesIn('A zombie stream: whales, whales and a Stream again; abduct.'), [
        'ZOMBIE',
        'STREAM',
        'WHALES',
        'ABDUCT',
      ]);
    });

    test('ignores words that are not candidates or not valid guesses', () {
      final g = WordGenerator(candidates: const ['stream', 'bricks'], guessList: const {'STREAM'});
      expect(g.candidatesIn('bricks by the stream, strands and streams'), ['STREAM']);
      expect(g.candidatesIn(''), isEmpty);
    });
  });

  test('containsWord requires a whole word, any case', () {
    expect(WordGenerator.containsWord('The Whales sang.', 'WHALES'), isTrue);
    expect(WordGenerator.containsWord('whales', 'WHALES'), isTrue);
    expect(WordGenerator.containsWord('narwhales', 'WHALES'), isFalse);
    expect(WordGenerator.containsWord('whalesong', 'WHALES'), isFalse);
  });
}

String _filler(int i) {
  final tail = StringBuffer();
  var n = i;
  for (var k = 0; k < 5; k++) {
    tail.writeCharCode(97 + n % 26);
    n ~/= 26;
  }
  return 'q$tail';
}

Set<String> _readWords(String path, {bool uppercase = false}) => {
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty) uppercase ? line.trim().toUpperCase() : line.trim().toLowerCase(),
};
