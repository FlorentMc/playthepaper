import 'dart:convert';
import 'dart:math';

import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'word_puzzle.dart';

/// A story-seeded answer: the word, the story it came from, the teaser shown
/// before play and the sentence from the story that contains the word.
class WordSeed {
  const WordSeed({required this.answer, required this.storyId, required this.teaser, required this.excerpt});

  final String answer;
  final String storyId;
  final String teaser;
  final String excerpt;
}

/// Deterministic Daily Word generation. Unseeded, the answer is read from a
/// fixed shuffle of the candidate list so a date always yields the same word
/// as long as the word lists and filters do not change. Seeded, the answer
/// comes from a story and the record carries the teaser and the excerpt.
class WordGenerator {
  WordGenerator({required List<String> candidates, required Set<String> guessList})
    : candidates = List.unmodifiable(candidates),
      guessList = Set.unmodifiable(guessList),
      _candidateSet = candidates.toSet(),
      _schedule = List<String>.from(candidates)..shuffle(Random(scheduleSeed));

  static const String dictionaryVersion = 'enable1-2026-09';
  static const int wordLength = 6;
  static const int maxGuesses = 6;
  static const int preferredRank = 25000;
  static const int relaxedRank = 40000;
  static const int minCandidates = 600;
  static const int scheduleSeed = 20260901;
  static final DateTime scheduleEpoch = DateTime.utc(2026, 9, 1);

  static const Set<String> blocklist = {
    'nigger',
    'nigras',
    'faggot',
    'honkey',
    'whitey',
    'tranny',
    'retard',
    'spooks',
    'fucked',
    'fucker',
    'shitty',
    'wanker',
    'bitchy',
    'pissed',
    'cummed',
    'boners',
  };

  static final RegExp _lowerWord = RegExp(r'^[a-z]+$');
  static final RegExp _upperAnswer = RegExp(r'^[A-Z]{6}$');
  static final RegExp _letterRun = RegExp(r'[A-Za-z]+');

  /// The sorted candidate answers, lowercase.
  final List<String> candidates;

  /// Every valid guess, uppercase; the answer must be one of them.
  final Set<String> guessList;

  final Set<String> _candidateSet;
  final List<String> _schedule;

  /// The sorted candidate answers: common six-letter words from [enable],
  /// without plurals, trivial inflections or offensive words. [rankOf] maps a
  /// word to its 1-based frequency rank.
  static List<String> buildCandidates({required Set<String> enable, required Map<String, int> rankOf}) {
    List<String> filter(int maxRank) => [
      for (final word in enable)
        if (word.length == wordLength &&
            _lowerWord.hasMatch(word) &&
            (rankOf[word] ?? 1 << 30) <= maxRank &&
            !blocklist.contains(word) &&
            !_isInflection(word, enable))
          word,
    ]..sort();
    var candidates = filter(preferredRank);
    if (candidates.length < minCandidates) candidates = filter(relaxedRank);
    if (candidates.length < minCandidates) {
      throw StateError('Only ${candidates.length} candidates after relaxing the rank');
    }
    return candidates;
  }

  static bool _isInflection(String word, Set<String> enable) {
    if (word.endsWith('s') && enable.contains(word.substring(0, 5))) return true;
    if (word.endsWith('es') && enable.contains(word.substring(0, 4))) return true;
    if ((word.endsWith('ies') || word.endsWith('ied')) && enable.contains('${word.substring(0, 3)}y')) return true;
    if (word.endsWith('ed')) {
      final stem = word.substring(0, 4);
      if (enable.contains(stem) || enable.contains('${stem}e')) return true;
      if (stem[3] == stem[2] && enable.contains(stem.substring(0, 3))) return true;
    }
    if (word.endsWith('ing')) {
      final stem = word.substring(0, 3);
      if (enable.contains(stem) || enable.contains('${stem}e')) return true;
    }
    return false;
  }

  /// The scheduled answer for [date], uppercase.
  String answerFor(DateTime date) {
    final days = date.toUtc().difference(scheduleEpoch).inDays;
    return _schedule[days % _schedule.length].toUpperCase();
  }

  /// Candidate answers that appear in [text] as whole words, uppercase, in
  /// order of first appearance. Every one of them is a valid seed answer.
  List<String> candidatesIn(String text) {
    final found = <String>[];
    for (final m in _letterRun.allMatches(text)) {
      final word = m[0]!.toLowerCase();
      if (word.length != wordLength || !_candidateSet.contains(word)) continue;
      final upper = word.toUpperCase();
      if (guessList.contains(upper) && !found.contains(upper)) found.add(upper);
    }
    return found;
  }

  /// The puzzle record for [date]. Without a [seed] the scheduled answer is
  /// used. With one, the answer must be six uppercase letters, a valid guess,
  /// and a whole word of the excerpt; anything else throws [FormatException].
  PuzzleRecord generate(DateTime date, {WordSeed? seed}) {
    final String answer;
    if (seed == null) {
      answer = answerFor(date);
      if (!guessList.contains(answer)) throw StateError('Answer $answer is not in the guess list');
    } else {
      answer = seed.answer;
      if (!_upperAnswer.hasMatch(answer)) {
        throw FormatException('Seed answer must be $wordLength uppercase letters: "$answer"');
      }
      if (!guessList.contains(answer)) throw FormatException('Seed answer $answer is not in the guess list');
      if (seed.storyId.isEmpty) throw const FormatException('Seed needs a storyId');
      if (seed.teaser.isEmpty) throw const FormatException('Seed needs a teaser');
      if (!containsWord(seed.excerpt, answer)) {
        throw FormatException('Seed excerpt does not contain $answer as a whole word');
      }
    }
    final puzzle = WordPuzzle(length: wordLength, firstLetter: answer[0], maxGuesses: maxGuesses, answer: answer);
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.word, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      dictionaryVersion: dictionaryVersion,
      payload: {...puzzle.toPayload(), if (seed != null) 'teaser': seed.teaser},
      reveal: {
        ...puzzle.toReveal(),
        if (seed != null) 'storyId': seed.storyId,
        if (seed != null) 'excerpt': seed.excerpt,
      },
      storyId: seed?.storyId,
    );
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    if (WordPuzzle.parse(check.payload, check.reveal) != puzzle) throw StateError('Round trip failed for ${record.id}');
    return record;
  }

  /// True when [word] occurs in [text] as a whole word, ignoring case.
  static bool containsWord(String text, String word) =>
      RegExp('(?<![A-Za-z])${RegExp.escape(word)}(?![A-Za-z])', caseSensitive: false).hasMatch(text);
}
