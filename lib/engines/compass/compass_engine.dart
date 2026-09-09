import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Word Compass: guess a hidden word by how close each guess is to it.
///
/// Closeness is a rank in a list of the target's nearest words, computed at
/// content time from word vectors (see `tool/compass_prepare.py`). Rank 1 is
/// the nearest word; the target itself is not in the list. A guess outside
/// the list is simply "far". This file is pure Dart: parsing, normalisation,
/// state and scoring. The generator that reads prepared rank files lives in
/// `compass_generator.dart` because it needs `dart:io`.

/// How close a guess is, in words. Every state pairs with a label so colour
/// never carries the meaning alone.
enum Proximity {
  found('found'),
  veryClose('very close'),
  close('close'),
  warm('warm'),
  far('far');

  const Proximity(this.label);
  final String label;
}

/// The puzzle: the target, how many words are ranked, and the ranks.
class CompassPuzzle extends Equatable {
  CompassPuzzle._({required this.target, required this.vocabularySize, required Map<String, int> ranks})
    : ranks = Map.unmodifiable(ranks),
      _byRank = List.unmodifiable(_ordered(ranks, vocabularySize));

  final String target;

  /// The number of ranked words; ranks run 1..[vocabularySize].
  final int vocabularySize;

  /// Word to rank, 1 = nearest. The target is not a key.
  final Map<String, int> ranks;

  final List<String> _byRank;

  static final RegExp _lowerWord = RegExp(r'^[a-z]+$');

  static List<String> _ordered(Map<String, int> ranks, int size) {
    final words = List<String>.filled(size, '');
    for (final e in ranks.entries) {
      words[e.value - 1] = e.key;
    }
    return words;
  }

  /// Parses a record's payload and reveal. Throws [FormatException] when the
  /// target is not a lowercase word, the ranks are not exactly the integers
  /// 1..vocabularySize once each, or the target appears among them.
  static CompassPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final size = payload['vocabularySize'];
    if (size is! int || size < 1) throw const FormatException('Compass payload needs a positive "vocabularySize"');
    final target = reveal['target'];
    if (target is! String || !_lowerWord.hasMatch(target)) {
      throw const FormatException('Compass reveal needs a lowercase a-z "target"');
    }
    final raw = reveal['ranks'];
    if (raw is! Map) throw const FormatException('Compass reveal needs a "ranks" map');
    if (raw.length != size) {
      throw FormatException('Compass ranks has ${raw.length} entries, vocabularySize is $size');
    }
    final ranks = <String, int>{};
    final seen = List<bool>.filled(size, false);
    for (final entry in raw.entries) {
      final word = entry.key;
      final rank = entry.value;
      if (word is! String || !_lowerWord.hasMatch(word)) {
        throw FormatException('Compass rank key "$word" is not a lowercase a-z word');
      }
      if (word == target) throw FormatException('Compass target "$target" must not be ranked');
      if (rank is! int || rank < 1 || rank > size) {
        throw FormatException('Compass rank for "$word" must be an integer in 1..$size, got $rank');
      }
      if (seen[rank - 1]) throw FormatException('Compass rank $rank appears twice');
      seen[rank - 1] = true;
      ranks[word] = rank;
    }
    return CompassPuzzle._(target: target, vocabularySize: size, ranks: ranks);
  }

  Map<String, dynamic> toPayload() => {'vocabularySize': vocabularySize};

  Map<String, dynamic> toReveal() => {'target': target, 'ranks': ranks};

  /// Lower-cases, trims and folds accents to ASCII so "  Café " matches "cafe".
  static String normalise(String input) {
    final lower = input.trim().toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      out.write(_folds[ch] ?? ch);
    }
    return out.toString();
  }

  /// True when the normalised input is a plain a-z word.
  static bool isWord(String normalised) => _lowerWord.hasMatch(normalised);

  bool isTarget(String word) => normalise(word) == target;

  /// The rank of [word] after normalisation, or null when it is not in the
  /// list (including the target itself: use [isTarget]).
  int? rankOf(String word) => ranks[normalise(word)];

  /// The word at [rank], 1..vocabularySize.
  String wordAt(int rank) {
    if (rank < 1 || rank > vocabularySize) throw RangeError.range(rank, 1, vocabularySize);
    return _byRank[rank - 1];
  }

  /// Proximity band for a rank; null means not in the list.
  Proximity proximityOf(int? rank) {
    if (rank == null) return Proximity.far;
    if (rank <= math.max(1, vocabularySize ~/ 100)) return Proximity.veryClose;
    if (rank <= math.max(1, vocabularySize ~/ 10)) return Proximity.close;
    return Proximity.warm;
  }

  /// A 0..1 measure for a proximity bar: 1 at rank 1, near 0 at the last
  /// rank, 0 outside the list. Logarithmic so early progress is visible.
  double proximityFraction(int? rank) {
    if (rank == null) return 0;
    if (vocabularySize <= 1) return 1;
    final f = 1 - math.log(rank) / math.log(vocabularySize + 1);
    return f.clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [target, vocabularySize, ranks];

  static const Map<String, String> _folds = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
    'æ': 'ae', 'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
    'ğ': 'g', 'ĝ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i',
    'ł': 'l', 'ľ': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'œ': 'oe',
    'ŕ': 'r', 'ř': 'r', 'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ß': 'ss', 'ţ': 't', 'ť': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
    'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
  };
}

/// One submitted guess: the normalised word, its rank (null when not in the
/// list), whether it is the target, and whether a hint supplied it.
class CompassGuess extends Equatable {
  const CompassGuess({required this.word, required this.rank, required this.isTarget, this.isHint = false});

  final String word;
  final int? rank;
  final bool isTarget;
  final bool isHint;

  /// Sort key: the target first, then by rank, then unranked words.
  int get order => isTarget ? 0 : (rank ?? 1 << 30);

  Map<String, dynamic> toJson() => {'word': word, if (isHint) 'hint': true};

  @override
  List<Object?> get props => [word, rank, isTarget, isHint];
}

/// The guesses of one play, in the order they were made. Immutable: [submit],
/// [hint] and [giveUp] return new states. Only words and flags are persisted;
/// ranks are derived from the puzzle.
class CompassState extends Equatable {
  const CompassState._({required this.puzzle, required this.guesses, required this.gaveUp});

  const CompassState.initial(CompassPuzzle puzzle) : this._(puzzle: puzzle, guesses: const [], gaveUp: false);

  final CompassPuzzle puzzle;
  final List<CompassGuess> guesses;
  final bool gaveUp;

  bool get solved => guesses.any((g) => g.isTarget);
  bool get isOver => solved || gaveUp;

  /// The player's own guesses, hints excluded.
  int get attempts => guesses.where((g) => !g.isHint).length;
  int get hints => guesses.where((g) => g.isHint).length;

  /// The best guess so far: the target, else the lowest rank, else null.
  CompassGuess? get best {
    CompassGuess? best;
    for (final g in guesses) {
      if (g.isTarget) return g;
      if (g.rank == null) continue;
      if (best == null || g.rank! < best.rank!) best = g;
    }
    return best;
  }

  /// Best rank so far: 0 when solved, null when nothing ranked yet.
  int? get bestRank {
    final b = best;
    if (b == null) return null;
    return b.isTarget ? 0 : b.rank;
  }

  /// Guesses sorted nearest first, ties by submission order.
  List<CompassGuess> get sorted {
    final indexed = List.generate(guesses.length, (i) => i);
    indexed.sort((a, b) {
      final byRank = guesses[a].order.compareTo(guesses[b].order);
      return byRank != 0 ? byRank : a.compareTo(b);
    });
    return [for (final i in indexed) guesses[i]];
  }

  bool contains(String word) {
    final w = CompassPuzzle.normalise(word);
    return guesses.any((g) => g.word == w);
  }

  /// Adds a guess. The caller checks [CompassPuzzle.isWord] and [contains]
  /// first; this throws [ArgumentError] for a non-word or a repeat and
  /// [StateError] once the play is over.
  CompassState submit(String input) {
    if (isOver) throw StateError('The puzzle is over');
    final word = CompassPuzzle.normalise(input);
    if (!CompassPuzzle.isWord(word)) throw ArgumentError('Guess "$input" is not a word of letters a-z');
    if (contains(word)) throw ArgumentError('Guess "$word" was already made');
    return _add(CompassGuess(word: word, rank: puzzle.ranks[word], isTarget: word == puzzle.target));
  }

  /// The rank a hint would reveal: half the best rank so far (half the list
  /// when nothing is ranked yet), moved closer past words already on the
  /// board. Null when no hint is possible.
  int? get hintRank {
    if (isOver) return null;
    final b = bestRank;
    var rank = b == null ? puzzle.vocabularySize ~/ 2 : b ~/ 2;
    if (rank < 1) rank = 1;
    final words = {for (final g in guesses) g.word};
    while (rank >= 1 && words.contains(puzzle.wordAt(rank))) {
      rank--;
    }
    return rank >= 1 ? rank : null;
  }

  bool get canHint => hintRank != null;

  /// Reveals the word at [hintRank] as a counted hint.
  CompassState hint() {
    final rank = hintRank;
    if (rank == null) throw StateError('No hint is available');
    return _add(CompassGuess(word: puzzle.wordAt(rank), rank: rank, isTarget: false, isHint: true));
  }

  /// Ends the play without solving it.
  CompassState giveUp() {
    if (isOver) throw StateError('The puzzle is over');
    return CompassState._(puzzle: puzzle, guesses: guesses, gaveUp: true);
  }

  CompassState _add(CompassGuess guess) =>
      CompassState._(puzzle: puzzle, guesses: List.unmodifiable([...guesses, guess]), gaveUp: gaveUp);

  /// One spoiler-free line for the share card.
  List<String> shareLines() {
    final n = attempts;
    final guessWord = n == 1 ? 'guess' : 'guesses';
    final h = hints == 0 ? '' : ' · $hints hint${hints == 1 ? '' : 's'}';
    if (solved) return ['🧭 solved in $n $guessWord$h'];
    final b = bestRank;
    final closest = b == null ? '' : ', closest #$b';
    return ['🧭 gave up after $n $guessWord$closest$h'];
  }

  /// A one-line summary for the result screen.
  String summary() {
    final n = attempts;
    final guessWord = n == 1 ? 'guess' : 'guesses';
    final h = hints == 0 ? '' : ' · $hints hint${hints == 1 ? '' : 's'}';
    return solved ? 'Solved in $n $guessWord$h' : 'Not solved · $n $guessWord$h';
  }

  Map<String, dynamic> toJson() => {
    'guesses': [for (final g in guesses) g.toJson()],
    if (gaveUp) 'gaveUp': true,
  };

  /// Rebuilds a state from [toJson]. Throws [FormatException] when the saved
  /// guesses cannot belong to [puzzle].
  static CompassState fromJson(CompassPuzzle puzzle, Map<String, dynamic> json) {
    final raw = json['guesses'];
    if (raw is! List) throw const FormatException('Compass progress needs "guesses"');
    var state = CompassState.initial(puzzle);
    for (final item in raw) {
      if (item is! Map) throw FormatException('Compass progress has an invalid guess: $item');
      final word = item['word'];
      if (word is! String || !CompassPuzzle.isWord(word)) {
        throw FormatException('Compass progress has an invalid guess word: $word');
      }
      if (state.isOver) throw const FormatException('Compass progress has guesses after the end');
      if (state.contains(word)) throw FormatException('Compass progress repeats "$word"');
      final isHint = item['hint'] == true;
      if (isHint) {
        final rank = puzzle.ranks[word];
        if (rank == null) throw FormatException('Compass progress hint "$word" is not a ranked word');
        state = state._add(CompassGuess(word: word, rank: rank, isTarget: false, isHint: true));
      } else {
        state = state.submit(word);
      }
    }
    if (json['gaveUp'] == true) {
      if (state.solved) throw const FormatException('Compass progress is both solved and given up');
      state = state.giveUp();
    }
    return state;
  }

  @override
  List<Object?> get props => [puzzle, guesses, gaveUp];
}
