import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'linked_puzzle.dart';
import 'linked_text.dart';

/// What the player has answered, which hints they have taken and whether the
/// puzzle is over. Immutable: every transition returns a new state.
///
/// Nothing is stored that could be worked out again: a set counts as solved
/// when one of its guesses is accepted by the puzzle, so restoring progress
/// re-checks every guess against the rules rather than trusting a flag.
///
/// Scoring: [LinkedPuzzle.maxPoints] to start, one off per hint and one off
/// per wrong guess at the final subject, never below
/// [LinkedPuzzle.minPointsWhenSolved] once solved. Giving up scores nothing.
class LinkedState extends Equatable {
  const LinkedState._({
    required this.puzzle,
    required this.setGuesses,
    required this.finalGuesses,
    required this.hintsShown,
    required this.gaveUp,
  });

  const LinkedState.initial(LinkedPuzzle puzzle)
      : this._(
          puzzle: puzzle,
          setGuesses: const [[], [], []],
          finalGuesses: const [],
          hintsShown: const [false, false, false, false],
          gaveUp: false,
        );

  /// The index of the final subject in [hintsShown].
  static const int finalHintIndex = LinkedPuzzle.setCount;

  final LinkedPuzzle puzzle;

  /// Guesses made against each set, in the order they were made.
  final List<List<String>> setGuesses;

  /// Guesses made at the final subject.
  final List<String> finalGuesses;

  /// Which hints have been taken: one per set, then the final subject's.
  final List<bool> hintsShown;

  final bool gaveUp;

  bool isSetSolved(int index) => setGuesses[index].any((g) => puzzle.acceptsAt(index, g));

  /// The accepted guess for a set, as the player typed it, or null.
  String? answerGiven(int index) =>
      setGuesses[index].where((g) => puzzle.acceptsAt(index, g)).firstOrNull;

  bool isHintShown(int index) => hintsShown[index];

  bool get isFinalHintShown => hintsShown[finalHintIndex];

  int get solvedSets => [for (var i = 0; i < LinkedPuzzle.setCount; i++) isSetSolved(i)].where((s) => s).length;

  bool get isSolved => finalGuesses.any(puzzle.acceptsFinal);

  bool get isOver => isSolved || gaveUp;

  int get hints => hintsShown.where((h) => h).length;

  int get wrongFinalGuesses => finalGuesses.where((g) => !puzzle.acceptsFinal(g)).length;

  int get attempts => finalGuesses.length + setGuesses.fold(0, (sum, g) => sum + g.length);

  int get points => isSolved
      ? math.max(LinkedPuzzle.minPointsWhenSolved, LinkedPuzzle.maxPoints - hints - wrongFinalGuesses)
      : 0;

  /// What the puzzle is worth if it is solved with the next guess.
  int get pointsOnOffer => math.max(LinkedPuzzle.minPointsWhenSolved, LinkedPuzzle.maxPoints - hints - wrongFinalGuesses);

  bool alreadyGuessedAt(int index, String raw) => _repeats(setGuesses[index], raw);

  bool alreadyGuessedFinal(String raw) => _repeats(finalGuesses, raw);

  static bool _repeats(List<String> guesses, String raw) {
    final normalised = LinkedText.normalise(raw);
    return normalised.isNotEmpty && guesses.any((g) => LinkedText.normalise(g) == normalised);
  }

  /// Answers set [index]. Returns this state unchanged when play is over,
  /// the set is already solved, the guess has nothing to match, or the same
  /// guess has already been tried there.
  LinkedState guessSet(int index, String raw) {
    final text = raw.trim();
    if (isOver || isSetSolved(index) || LinkedText.normalise(text).isEmpty || alreadyGuessedAt(index, text)) {
      return this;
    }
    final next = [for (var i = 0; i < setGuesses.length; i++) if (i == index) [...setGuesses[i], text] else setGuesses[i]];
    return _copy(setGuesses: next);
  }

  /// Guesses the final subject. A wrong guess costs a point.
  LinkedState guessFinal(String raw) {
    final text = raw.trim();
    if (isOver || LinkedText.normalise(text).isEmpty || alreadyGuessedFinal(text)) return this;
    return _copy(finalGuesses: [...finalGuesses, text]);
  }

  /// Shows the hint for a set, or for the final subject at
  /// [finalHintIndex]. Costs a point. A solved set's hint is not offered.
  LinkedState showHint(int index) {
    if (isOver || hintsShown[index]) return this;
    if (index != finalHintIndex && isSetSolved(index)) return this;
    final next = List<bool>.of(hintsShown)..[index] = true;
    return _copy(hintsShown: next);
  }

  LinkedState giveUp() => isOver ? this : _copy(gaveUp: true);

  /// A one-line summary for the result screen.
  String summary() {
    if (!isSolved) return 'Not solved · $solvedSets of ${LinkedPuzzle.setCount} sets';
    final parts = <String>['Solved · $points of ${LinkedPuzzle.maxPoints}'];
    if (hints > 0) parts.add('$hints hint${hints == 1 ? '' : 's'}');
    if (wrongFinalGuesses > 0) {
      parts.add('$wrongFinalGuesses wrong guess${wrongFinalGuesses == 1 ? '' : 'es'}');
    }
    return parts.join(' · ');
  }

  /// Spoiler-free rows for the share card: the score, then a mark per set and
  /// one for the final subject. Green is unaided, amber took a hint.
  List<String> shareLines() {
    String mark(bool solved, bool hinted) => !solved
        ? '🟥'
        : hinted
            ? '🟨'
            : '🟩';
    final sets = [
      for (var i = 0; i < LinkedPuzzle.setCount; i++) mark(isSetSolved(i), hintsShown[i]),
    ].join();
    return [
      '🔗 $points/${LinkedPuzzle.maxPoints}',
      '$sets → ${mark(isSolved, isFinalHintShown)}',
    ];
  }

  Map<String, dynamic> toJson() => {
        'sets': setGuesses,
        'final': finalGuesses,
        'hints': hintsShown,
        'gaveUp': gaveUp,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not describe a possible run of play.
  static LinkedState fromJson(LinkedPuzzle puzzle, Map<String, dynamic> json) {
    List<String> guesses(Object? raw, String where, bool Function(String) accepts) {
      if (raw is! List) throw FormatException('Linked progress "$where" must be a list');
      final out = <String>[];
      final seen = <String>{};
      for (final entry in raw) {
        if (entry is! String || entry.trim().isEmpty) {
          throw FormatException('Linked progress "$where" holds a guess with no text');
        }
        final text = entry.trim();
        if (!seen.add(LinkedText.normalise(text))) {
          throw FormatException('Linked progress "$where" repeats the guess "$text"');
        }
        if (out.isNotEmpty && accepts(out.last)) {
          throw FormatException('Linked progress "$where" carries on after the right answer');
        }
        out.add(text);
      }
      return List.unmodifiable(out);
    }

    final rawSets = json['sets'];
    if (rawSets is! List || rawSets.length != LinkedPuzzle.setCount) {
      throw const FormatException('Linked progress "sets" must hold one list of guesses per set');
    }
    final setGuesses = [
      for (var i = 0; i < LinkedPuzzle.setCount; i++)
        guesses(rawSets[i], 'sets', (g) => puzzle.acceptsAt(i, g)),
    ];
    final finalGuesses = guesses(json['final'], 'final', puzzle.acceptsFinal);

    final rawHints = json['hints'];
    if (rawHints is! List || rawHints.length != LinkedPuzzle.setCount + 1 || rawHints.any((h) => h is! bool)) {
      throw const FormatException('Linked progress "hints" must hold one flag per set and one for the final');
    }
    final hints = rawHints.cast<bool>();
    final gaveUp = json['gaveUp'] == true;
    final solved = finalGuesses.any(puzzle.acceptsFinal);
    if (gaveUp && solved) throw const FormatException('Linked progress both solves and gives up');
    return LinkedState._(
      puzzle: puzzle,
      setGuesses: List.unmodifiable(setGuesses),
      finalGuesses: finalGuesses,
      hintsShown: List.unmodifiable(hints),
      gaveUp: gaveUp,
    );
  }

  LinkedState _copy({
    List<List<String>>? setGuesses,
    List<String>? finalGuesses,
    List<bool>? hintsShown,
    bool? gaveUp,
  }) =>
      LinkedState._(
        puzzle: puzzle,
        setGuesses:
            setGuesses == null ? this.setGuesses : List.unmodifiable(setGuesses.map(List<String>.unmodifiable)),
        finalGuesses: finalGuesses == null ? this.finalGuesses : List.unmodifiable(finalGuesses),
        hintsShown: hintsShown == null ? this.hintsShown : List.unmodifiable(hintsShown),
        gaveUp: gaveUp ?? this.gaveUp,
      );

  @override
  List<Object?> get props => [puzzle, setGuesses, finalGuesses, hintsShown, gaveUp];
}
