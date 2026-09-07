import 'dart:convert';
import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'letters_puzzle.dart';

/// A story-seeded pangram: the word, the story it came from, the teaser
/// shown before play and the sentence from the story that contains it.
class LettersSeed {
  const LettersSeed({required this.pangram, required this.storyId, required this.teaser, required this.excerpt});

  final String pangram;
  final String storyId;
  final String teaser;
  final String excerpt;
}

/// A word of the generation pool, lowercase, with its frequency rank and the
/// bitmask of its letters.
class PoolWord {
  PoolWord(this.word, this.rank) : mask = LettersGenerator.maskOf(word);

  final String word;
  final int rank;
  final int mask;
}

/// Deterministic Letters generation from a frequency-ranked pool. Unseeded,
/// the seven letters come from a common pangram chosen by a per-date shuffle
/// and skip any set in [usedSets]. Seeded, the letters are those of the
/// story's pangram, tried with each centre in a per-date order.
class LettersGenerator {
  LettersGenerator({required List<PoolWord> pool})
    : pool = List.unmodifiable(pool),
      _poolWords = {for (final p in pool) p.word: p},
      pangramCandidates = List.unmodifiable(
        pool.where((p) => p.rank <= pangramMaxRank && bitCount(p.mask) == 7 && !p.word.contains('s')),
      );

  static const String dictionaryVersion = 'enable1-en50k-2026-09';
  static const int poolMaxRank = 50000;
  static const int pangramMaxRank = 30000;
  static const int commonMaxRank = 20000;
  static const int minAnswers = 20;
  static const int maxAnswers = 80;
  static const int minCommonAnswers = 12;
  static const int minLength = 4;

  static const Set<String> blocklist = {
    'anal',
    'anus',
    'arse',
    'arses',
    'bitch',
    'bitches',
    'bitching',
    'boner',
    'boners',
    'chink',
    'chinks',
    'clit',
    'cock',
    'cocks',
    'coon',
    'coons',
    'crap',
    'craps',
    'cunt',
    'cunts',
    'dago',
    'dagos',
    'damn',
    'damned',
    'dick',
    'dicks',
    'dike',
    'dikes',
    'dyke',
    'dykes',
    'fags',
    'faggot',
    'faggots',
    'fuck',
    'fucked',
    'fucker',
    'fuckers',
    'fucking',
    'fucks',
    'gook',
    'gooks',
    'homo',
    'homos',
    'jism',
    'kike',
    'kikes',
    'kraut',
    'krauts',
    'nazi',
    'nazis',
    'negro',
    'negroes',
    'nigga',
    'niggas',
    'nigger',
    'niggers',
    'paki',
    'pakis',
    'penis',
    'penises',
    'piss',
    'pissed',
    'pisses',
    'pissing',
    'porn',
    'porno',
    'prick',
    'pricks',
    'pube',
    'pubes',
    'pussies',
    'pussy',
    'queer',
    'queers',
    'rape',
    'raped',
    'raper',
    'rapes',
    'raping',
    'rapist',
    'rapists',
    'retard',
    'retarded',
    'retards',
    'semen',
    'shit',
    'shits',
    'shitted',
    'shitting',
    'shitty',
    'slut',
    'sluts',
    'spic',
    'spick',
    'spics',
    'tits',
    'titties',
    'titty',
    'tranny',
    'turd',
    'turds',
    'twat',
    'twats',
    'wank',
    'wanked',
    'wanker',
    'wankers',
    'wanking',
    'wanks',
    'wetback',
    'whore',
    'whores',
    'whoring',
    'wog',
    'wogs',
    'wop',
    'wops',
  };

  static final RegExp _lowerWord = RegExp(r'^[a-z]+$');
  static final RegExp _upperWord = RegExp(r'^[A-Z]+$');
  static final RegExp _letterRun = RegExp(r'[A-Za-z]+');

  /// Every accepted word, by rank.
  final List<PoolWord> pool;

  /// The common seven-letter-set words unseeded generation draws from.
  final List<PoolWord> pangramCandidates;

  /// Letter sets already published, as masks. Unseeded generation never
  /// reuses one, and every successful [generate] adds its set here.
  final Set<int> usedSets = {};

  final Map<String, PoolWord> _poolWords;

  /// The pool: words of [rankedWords] (most frequent first, first
  /// [poolMaxRank] considered) that are at least [minLength] lowercase
  /// letters, in [enable] and not blocklisted, sorted by rank.
  static List<PoolWord> buildPool({required Set<String> enable, required List<String> rankedWords}) {
    final ranks = <String, int>{};
    for (var i = 0; i < rankedWords.length && i < poolMaxRank; i++) {
      ranks.putIfAbsent(rankedWords[i], () => i + 1);
    }
    final pool = <PoolWord>[];
    for (final entry in ranks.entries) {
      final w = entry.key;
      if (w.length < minLength || !_lowerWord.hasMatch(w) || blocklist.contains(w) || !enable.contains(w)) continue;
      pool.add(PoolWord(w, entry.value));
    }
    pool.sort((a, b) => a.rank.compareTo(b.rank));
    return pool;
  }

  /// 32-bit FNV-1a over the UTF-8 bytes of [text].
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(text)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// One bit per letter of [word], whatever its case.
  static int maskOf(String word) {
    var mask = 0;
    for (final c in word.toLowerCase().codeUnits) {
      mask |= _letterBit(c);
    }
    return mask;
  }

  static int _letterBit(int codeUnit) => 1 << (codeUnit - 0x61);

  static int bitCount(int mask) {
    var n = 0;
    while (mask != 0) {
      mask &= mask - 1;
      n++;
    }
    return n;
  }

  /// Records the letter set of a published puzzle so it is not reused.
  void markUsed(Iterable<String> letters) => usedSets.add(maskOf(letters.join()));

  /// Pool words in [text] with exactly seven distinct letters, uppercase, in
  /// order of first appearance. Each is a valid seed pangram, though its
  /// letter set may still fail the answer-count constraints.
  List<String> pangramCandidatesIn(String text) {
    final found = <String>[];
    for (final m in _letterRun.allMatches(text)) {
      final word = m[0]!.toLowerCase();
      final entry = _poolWords[word];
      if (entry == null || bitCount(entry.mask) != 7) continue;
      final upper = word.toUpperCase();
      if (!found.contains(upper)) found.add(upper);
    }
    return found;
  }

  /// The puzzle record for [date], or null when no letter set satisfies the
  /// constraints. A bad [seed] throws [FormatException].
  PuzzleRecord? generate(DateTime date, {LettersSeed? seed}) {
    final dateText = EditionClock.formatDate(date);
    final random = Random(fnv1a('letters-$dateText'));
    final _Generated? generated;
    if (seed == null) {
      generated = _generateScheduled(random);
    } else {
      _validateSeed(seed);
      final pangram = _poolWords[seed.pangram.toLowerCase()]!;
      final letters = pangram.word.split('').toSet().toList()..shuffle(random);
      generated = _firstValid(pangram, letters);
    }
    if (generated == null) return null;
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.letters, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      dictionaryVersion: dictionaryVersion,
      payload: {
        'center': generated.center,
        'outer': generated.outer,
        'minLength': minLength,
        if (seed != null) 'teaser': seed.teaser,
      },
      reveal: {
        'answers': generated.answers,
        'pangrams': generated.pangrams,
        'maxScore': generated.maxScore,
        if (seed != null) 'storyId': seed.storyId,
        if (seed != null) 'excerpt': seed.excerpt,
      },
      storyId: seed?.storyId,
    );
    final reparsed = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    final puzzle = LettersPuzzle.parse(reparsed.payload, reparsed.reveal);
    if (puzzle.answers.length != generated.answers.length || puzzle.maxScore != generated.maxScore) {
      throw StateError('Re-parsed puzzle for $dateText does not match what was generated');
    }
    if (seed != null && !puzzle.pangrams.contains(seed.pangram)) {
      throw StateError('Seed pangram ${seed.pangram} is not among the pangrams for $dateText');
    }
    usedSets.add(generated.mask);
    return record;
  }

  void _validateSeed(LettersSeed seed) {
    final pangram = seed.pangram;
    if (!_upperWord.hasMatch(pangram)) throw FormatException('Seed pangram must be uppercase letters: "$pangram"');
    if (pangram.length < 7) throw FormatException('Seed pangram must be at least 7 letters: $pangram');
    if (bitCount(maskOf(pangram)) != 7) {
      throw FormatException('Seed pangram must use exactly 7 distinct letters: $pangram');
    }
    if (!_poolWords.containsKey(pangram.toLowerCase())) {
      throw FormatException('Seed pangram $pangram is not in the pool');
    }
    if (seed.storyId.isEmpty) throw const FormatException('Seed needs a storyId');
    if (seed.teaser.isEmpty) throw const FormatException('Seed needs a teaser');
    if (!containsWord(seed.excerpt, pangram)) {
      throw FormatException('Seed excerpt does not contain $pangram as a whole word');
    }
  }

  _Generated? _generateScheduled(Random random) {
    final shuffled = pangramCandidates.toList()..shuffle(random);
    for (final candidate in shuffled) {
      if (usedSets.contains(candidate.mask)) continue;
      final letters = candidate.word.split('').toSet().toList()..shuffle(random);
      final generated = _firstValid(candidate, letters);
      if (generated != null) return generated;
    }
    return null;
  }

  _Generated? _firstValid(PoolWord candidate, List<String> centers) {
    final setMask = candidate.mask;
    for (final center in centers) {
      final centerBit = _letterBit(center.codeUnitAt(0));
      final answers = pool.where((p) => (p.mask & ~setMask) == 0 && (p.mask & centerBit) != 0).toList();
      if (answers.length < minAnswers || answers.length > maxAnswers) continue;
      if (answers.where((p) => p.rank <= commonMaxRank).length < minCommonAnswers) continue;
      final words = answers.map((p) => p.word.toUpperCase()).toList()..sort();
      final upperSet = candidate.word.toUpperCase().split('').toSet();
      final pangrams = words.where((w) => isPangram(w, letters: upperSet)).toList();
      final maxScore = words.fold(0, (sum, w) => sum + scoreWord(w, letters: upperSet));
      final outer =
          (upperSet.toList()
                ..remove(center.toUpperCase())
                ..sort())
              .join();
      return _Generated(center.toUpperCase(), outer, words, pangrams, maxScore, setMask);
    }
    return null;
  }

  /// True when [word] occurs in [text] as a whole word, ignoring case.
  static bool containsWord(String text, String word) =>
      RegExp('(?<![A-Za-z])${RegExp.escape(word)}(?![A-Za-z])', caseSensitive: false).hasMatch(text);
}

class _Generated {
  const _Generated(this.center, this.outer, this.answers, this.pangrams, this.maxScore, this.mask);

  final String center;
  final String outer;
  final List<String> answers;
  final List<String> pangrams;
  final int maxScore;
  final int mask;
}
