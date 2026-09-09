import 'dart:math';

import 'uncover_puzzle.dart';
import 'uncover_text.dart';

enum UncoverStatus { playing, solved, gaveUp }

/// Why a guess would not be applied, or that it would be.
enum UncoverCheck { empty, common, repeat, ok }

/// One submitted guess: the text as typed and how many words it revealed.
class UncoverGuess {
  const UncoverGuess({required this.word, required this.matches});

  final String word;
  final int matches;

  String get normalised => UncoverText.normalisePhrase(word);

  List<Object> toJson() => [word, matches];

  static UncoverGuess fromJson(Object? raw) {
    if (raw is! List || raw.length != 2 || raw[0] is! String || raw[1] is! int || (raw[1] as int) < 0) {
      throw const FormatException('Uncover guess must be [word, matches]');
    }
    return UncoverGuess(word: raw[0] as String, matches: raw[1] as int);
  }
}

/// The whole play state of one Uncover puzzle. Immutable: every transition
/// returns a new state.
///
/// Score: [maxPoints] less one per hint and one per five guesses, never
/// below 1 when solved; 0 when the player gave up.
class UncoverState {
  const UncoverState._({
    required this.puzzle,
    required this.guesses,
    required Set<String> guessed,
    required this.hintsUsed,
    required this.status,
  }) : _guessed = guessed;

  factory UncoverState.initial(UncoverPuzzle puzzle) => UncoverState._(
        puzzle: puzzle,
        guesses: const [],
        guessed: const {},
        hintsUsed: 0,
        status: UncoverStatus.playing,
      );

  static const int maxPoints = 10;
  static const int guessesPerPoint = 5;

  final UncoverPuzzle puzzle;
  final List<UncoverGuess> guesses;
  final Set<String> _guessed;
  final int hintsUsed;
  final UncoverStatus status;

  bool get isPlaying => status == UncoverStatus.playing;
  bool get isOver => status != UncoverStatus.playing;
  bool get isSolved => status == UncoverStatus.solved;

  UncoverGuess? get lastGuess => guesses.isEmpty ? null : guesses.last;

  int get guessCount => guesses.length;

  /// Guessable words of the text that are currently shown.
  int get revealedCount => puzzle.words.where((w) => w.isHidden && _guessed.contains(w.normalised)).length;

  int get hiddenCount => puzzle.hiddenCount;

  List<String> get revealedHints => puzzle.hints.take(hintsUsed).toList(growable: false);

  bool get canHint => isPlaying && hintsUsed < puzzle.hints.length;

  int get points => isSolved ? max(1, maxPoints - hintsUsed - guessCount ~/ guessesPerPoint) : 0;

  /// True when the word at [index] of [UncoverPuzzle.words] is shown.
  bool isRevealed(int index) {
    final w = puzzle.words[index];
    return switch (w.kind) {
      UncoverWordKind.separator || UncoverWordKind.common => true,
      UncoverWordKind.hidden => isOver || _guessed.contains(w.normalised),
      UncoverWordKind.subject => isOver,
    };
  }

  /// True when the word at [index] was revealed by the latest guess.
  bool isLatest(int index) {
    final last = lastGuess;
    final w = puzzle.words[index];
    return last != null && last.matches > 0 && w.isHidden && w.normalised == last.normalised;
  }

  bool hasGuessed(String raw) => _guessed.contains(UncoverText.normalisePhrase(raw));

  /// What [submit] would do with [raw].
  UncoverCheck check(String raw) {
    if (!isPlaying) return UncoverCheck.empty;
    if (puzzle.isAnswer(raw)) return UncoverCheck.ok;
    final n = UncoverText.normalisePhrase(raw);
    if (n.isEmpty) return UncoverCheck.empty;
    if (UncoverText.isCommon(n)) return UncoverCheck.common;
    if (_guessed.contains(n)) return UncoverCheck.repeat;
    return UncoverCheck.ok;
  }

  /// Applies a guess. Naming the subject solves the puzzle; any other word
  /// reveals its occurrences in the text (none for a subject word). Returns
  /// this state unchanged when [check] is not [UncoverCheck.ok].
  UncoverState submit(String raw) {
    if (check(raw) != UncoverCheck.ok) return this;
    final word = raw.trim();
    if (puzzle.isAnswer(word)) {
      return _copy(
        guesses: [...guesses, UncoverGuess(word: word, matches: 0)],
        status: UncoverStatus.solved,
      );
    }
    final n = UncoverText.normalisePhrase(word);
    return _copy(
      guesses: [...guesses, UncoverGuess(word: word, matches: puzzle.occurrences(n))],
      guessed: {..._guessed, n},
    );
  }

  UncoverState useHint() => canHint ? _copy(hintsUsed: hintsUsed + 1) : this;

  UncoverState giveUp() => isPlaying ? _copy(status: UncoverStatus.gaveUp) : this;

  /// Spoiler-free rows for the share card.
  List<String> shareLines() {
    if (!isSolved) return ['🔎 not uncovered · ${_guessLabel()}$_hintLabel'];
    return [
      '🔎 uncovered in ${_guessLabel()}$_hintLabel',
      [for (var i = 0; i < maxPoints; i++) i < points ? '🟩' : '⬜'].join(),
    ];
  }

  /// The one-line result summary, e.g. `Uncovered in 12 guesses`.
  String summary() =>
      isSolved ? 'Uncovered in ${_guessLabel()}$_hintLabel' : 'Not uncovered · ${_guessLabel()}$_hintLabel';

  String _guessLabel() => '$guessCount guess${guessCount == 1 ? '' : 'es'}';

  String get _hintLabel => hintsUsed == 0 ? '' : ' · $hintsUsed hint${hintsUsed == 1 ? '' : 's'}';

  Map<String, dynamic> toJson() => {
        'guesses': guesses.map((g) => g.toJson()).toList(),
        'hints': hintsUsed,
        'status': status.name,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed.
  static UncoverState fromJson(UncoverPuzzle puzzle, Map<String, dynamic> json) {
    final rawGuesses = json['guesses'];
    if (rawGuesses is! List) throw const FormatException('Uncover progress is missing "guesses"');
    final guesses = rawGuesses.map(UncoverGuess.fromJson).toList(growable: false);
    final hints = json['hints'];
    if (hints is! int || hints < 0 || hints > puzzle.hints.length) {
      throw const FormatException('Uncover progress "hints" is out of range');
    }
    final status = UncoverStatus.values.where((s) => s.name == json['status']).firstOrNull;
    if (status == null) throw const FormatException('Uncover progress "status" is unknown');
    final guessed = <String>{};
    for (var i = 0; i < guesses.length; i++) {
      final g = guesses[i];
      if (status == UncoverStatus.solved && i == guesses.length - 1) {
        if (!puzzle.isAnswer(g.word)) throw const FormatException('Uncover progress is solved without the subject');
        continue;
      }
      guessed.add(g.normalised);
    }
    return UncoverState._(
      puzzle: puzzle,
      guesses: List.unmodifiable(guesses),
      guessed: Set.unmodifiable(guessed),
      hintsUsed: hints,
      status: status,
    );
  }

  UncoverState _copy({
    List<UncoverGuess>? guesses,
    Set<String>? guessed,
    int? hintsUsed,
    UncoverStatus? status,
  }) =>
      UncoverState._(
        puzzle: puzzle,
        guesses: guesses == null ? this.guesses : List.unmodifiable(guesses),
        guessed: guessed == null ? _guessed : Set.unmodifiable(guessed),
        hintsUsed: hintsUsed ?? this.hintsUsed,
        status: status ?? this.status,
      );
}
