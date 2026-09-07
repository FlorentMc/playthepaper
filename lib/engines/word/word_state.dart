import 'package:equatable/equatable.dart';

import 'word_feedback.dart';
import 'word_puzzle.dart';

enum WordStatus { playing, won, lost }

/// Best feedback seen so far for a keyboard letter. Declared in ascending
/// order so a later, better state replaces an earlier one.
enum WordKeyState { absent, misplaced, correct }

/// The submitted guesses of one play, with their feedback. Immutable: [submit]
/// returns a new state. Only the guesses are persisted; feedback is derived.
class WordState extends Equatable {
  const WordState._({required this.puzzle, required this.guesses, required this.feedbacks});

  const WordState.initial(WordPuzzle puzzle) : this._(puzzle: puzzle, guesses: const [], feedbacks: const []);

  final WordPuzzle puzzle;
  final List<String> guesses;
  final List<List<LetterFeedback>> feedbacks;

  static final RegExp _upper = RegExp(r'^[A-Z]+$');

  WordStatus get status {
    if (guesses.isNotEmpty && guesses.last == puzzle.answer) return WordStatus.won;
    if (guesses.length >= puzzle.maxGuesses) return WordStatus.lost;
    return WordStatus.playing;
  }

  bool get isOver => status != WordStatus.playing;

  /// Adds a guess. The caller validates it with `validateGuess` first; this
  /// only requires the right length and uppercase letters.
  WordState submit(String guess) {
    if (isOver) throw StateError('The puzzle is over');
    final word = guess.toUpperCase();
    if (word.length != puzzle.length || !_upper.hasMatch(word)) {
      throw ArgumentError('Guess "$guess" is not ${puzzle.length} letters A-Z');
    }
    return WordState._(
      puzzle: puzzle,
      guesses: List.unmodifiable([...guesses, word]),
      feedbacks: List.unmodifiable([...feedbacks, evaluateGuess(word, puzzle.answer)]),
    );
  }

  /// The best feedback for each guessed letter: correct beats misplaced beats absent.
  Map<String, WordKeyState> keyStates() {
    final states = <String, WordKeyState>{};
    for (var g = 0; g < guesses.length; g++) {
      for (var i = 0; i < guesses[g].length; i++) {
        final letter = guesses[g][i];
        final next = switch (feedbacks[g][i]) {
          LetterFeedback.correct => WordKeyState.correct,
          LetterFeedback.misplaced => WordKeyState.misplaced,
          LetterFeedback.absent => WordKeyState.absent,
        };
        final current = states[letter];
        if (current == null || next.index > current.index) states[letter] = next;
      }
    }
    return states;
  }

  /// One spoiler-free emoji row per guess.
  List<String> shareLines() => [
    for (final row in feedbacks)
      row
          .map(
            (f) => switch (f) {
              LetterFeedback.correct => '🟩',
              LetterFeedback.misplaced => '🟨',
              LetterFeedback.absent => '⬜',
            },
          )
          .join(),
  ];

  Map<String, dynamic> toJson() => {'guesses': guesses};

  /// Rebuilds a state from [toJson]. Throws [FormatException] when the saved
  /// guesses cannot belong to [puzzle].
  static WordState fromJson(WordPuzzle puzzle, Map<String, dynamic> json) {
    final raw = json['guesses'];
    if (raw is! List) throw const FormatException('Word progress needs "guesses"');
    var state = WordState.initial(puzzle);
    for (final g in raw) {
      if (g is! String || g.length != puzzle.length || !_upper.hasMatch(g)) {
        throw FormatException('Word progress has an invalid guess: $g');
      }
      if (state.isOver) throw const FormatException('Word progress has guesses after the end');
      state = state.submit(g);
    }
    return state;
  }

  @override
  List<Object?> get props => [puzzle, guesses, feedbacks];
}
