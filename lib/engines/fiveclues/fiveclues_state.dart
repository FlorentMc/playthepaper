import 'package:equatable/equatable.dart';

import 'fiveclues_puzzle.dart';
import 'fiveclues_text.dart';

/// One guess: what the player typed, which clue was newest at the time, and
/// whether it was right.
class FiveCluesGuess extends Equatable {
  const FiveCluesGuess({required this.text, required this.clue, required this.correct});

  final String text;

  /// Zero-based index of the newest clue when the guess was made.
  final int clue;
  final bool correct;

  Map<String, dynamic> toJson() => {'text': text, 'clue': clue, 'correct': correct};

  @override
  List<Object?> get props => [text, clue, correct];
}

/// How far into the clues the player is, what they have guessed, and whether
/// play is over. Immutable: every transition returns a new state.
///
/// The first clue is there from the start. A wrong guess or a pass shows the
/// next clue; a wrong guess or a pass on the last clue ends the puzzle with
/// the answer revealed. There is no board, so nothing to undo: a shown clue
/// cannot be taken back.
class FiveCluesState extends Equatable {
  const FiveCluesState._({
    required this.puzzle,
    required this.guesses,
    required this.revealed,
    required this.gaveUp,
  });

  const FiveCluesState.initial(FiveCluesPuzzle puzzle)
      : this._(puzzle: puzzle, guesses: const [], revealed: 1, gaveUp: false);

  final FiveCluesPuzzle puzzle;

  /// Every guess in the order it was made.
  final List<FiveCluesGuess> guesses;

  /// How many clues are visible, 1 to [FiveCluesPuzzle.clueCount].
  final int revealed;

  /// True when the last clue ran out without a right answer.
  final bool gaveUp;

  /// The clue the player is working on, zero-based.
  int get currentClue => revealed - 1;

  List<String> get visibleClues => puzzle.clues.sublist(0, revealed);

  bool get isSolved => guesses.isNotEmpty && guesses.last.correct;

  bool get isOver => isSolved || gaveUp;

  bool get hasMoreClues => revealed < FiveCluesPuzzle.clueCount;

  int get attempts => guesses.length;

  /// The clue that was showing when the puzzle was solved, or null.
  int? get solvedOnClue => isSolved ? guesses.last.clue : null;

  /// What a right answer is worth now.
  int get pointsOnOffer => FiveCluesPuzzle.pointsForClue(currentClue);

  int get points => isSolved ? FiveCluesPuzzle.pointsForClue(guesses.last.clue) : 0;

  /// True when [raw] has already been tried, however it was spelled.
  bool alreadyGuessed(String raw) {
    final normalised = FiveCluesText.normalise(raw);
    return normalised.isNotEmpty && guesses.any((g) => FiveCluesText.normalise(g.text) == normalised);
  }

  /// Records a guess. A right answer ends the puzzle; a wrong one shows the
  /// next clue, or ends the puzzle when the clues run out. Returns this state
  /// unchanged when play is over, when [raw] has nothing to match, or when
  /// the same guess has already been tried.
  FiveCluesState guess(String raw) {
    if (isOver) return this;
    final text = raw.trim();
    if (FiveCluesText.normalise(text).isEmpty || alreadyGuessed(text)) return this;
    final correct = puzzle.accepts(text);
    final next = [...guesses, FiveCluesGuess(text: text, clue: currentClue, correct: correct)];
    if (correct) return _copy(guesses: next);
    return _copy(guesses: next, revealed: hasMoreClues ? revealed + 1 : revealed, gaveUp: !hasMoreClues);
  }

  /// Shows the next clue without guessing, or gives up on the last one. Not
  /// counted as an attempt, and worth the same as a wrong guess.
  FiveCluesState pass() {
    if (isOver) return this;
    return _copy(revealed: hasMoreClues ? revealed + 1 : revealed, gaveUp: !hasMoreClues);
  }

  /// A one-line summary for the result screen.
  String summary() {
    if (!isSolved) return 'Not solved · the answer was revealed';
    final clue = guesses.last.clue + 1;
    return 'Solved on clue $clue · $points point${points == 1 ? '' : 's'}';
  }

  /// Spoiler-free rows for the share card: how far in the answer came, then
  /// one mark per clue.
  List<String> shareLines() {
    final marks = [
      for (var i = 0; i < FiveCluesPuzzle.clueCount; i++)
        if (isSolved && i == guesses.last.clue)
          '🟩'
        else if (i < revealed)
          '🟥'
        else
          '⬜',
    ].join();
    return [isSolved ? '🔗 solved on clue ${guesses.last.clue + 1}' : '🔗 not solved', marks];
  }

  Map<String, dynamic> toJson() => {
        'guesses': guesses.map((g) => g.toJson()).toList(),
        'revealed': revealed,
        'gaveUp': gaveUp,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not describe a possible run of play.
  static FiveCluesState fromJson(FiveCluesPuzzle puzzle, Map<String, dynamic> json) {
    final revealed = json['revealed'];
    if (revealed is! int || revealed < 1 || revealed > FiveCluesPuzzle.clueCount) {
      throw const FormatException('Five Clues progress "revealed" is out of range');
    }
    final rawGuesses = json['guesses'];
    if (rawGuesses is! List) throw const FormatException('Five Clues progress "guesses" must be a list');
    final guesses = <FiveCluesGuess>[];
    for (final raw in rawGuesses) {
      if (raw is! Map) throw const FormatException('Five Clues progress has a malformed guess');
      final text = raw['text'];
      final clue = raw['clue'];
      if (text is! String || text.trim().isEmpty) {
        throw const FormatException('Five Clues progress has a guess with no text');
      }
      if (clue is! int || clue < 0 || clue >= revealed) {
        throw const FormatException('Five Clues progress has a guess on a clue that was not shown');
      }
      if (guesses.isNotEmpty && clue < guesses.last.clue) {
        throw const FormatException('Five Clues progress has guesses out of order');
      }
      if (guesses.isNotEmpty && guesses.last.correct) {
        throw const FormatException('Five Clues progress carries on after a right answer');
      }
      final correct = puzzle.accepts(text);
      if (raw['correct'] is bool && raw['correct'] != correct) {
        throw const FormatException('Five Clues progress disagrees with the answer');
      }
      guesses.add(FiveCluesGuess(text: text.trim(), clue: clue, correct: correct));
    }
    final gaveUp = json['gaveUp'] == true;
    if (gaveUp && revealed != FiveCluesPuzzle.clueCount) {
      throw const FormatException('Five Clues progress gives up before the last clue');
    }
    final wrong = guesses.where((g) => !g.correct).length;
    if (wrong > revealed - 1 + (gaveUp ? 1 : 0)) {
      throw const FormatException('Five Clues progress has more wrong guesses than clues shown');
    }
    return FiveCluesState._(
      puzzle: puzzle,
      guesses: List.unmodifiable(guesses),
      revealed: revealed,
      gaveUp: gaveUp,
    );
  }

  FiveCluesState _copy({List<FiveCluesGuess>? guesses, int? revealed, bool? gaveUp}) => FiveCluesState._(
        puzzle: puzzle,
        guesses: guesses == null ? this.guesses : List.unmodifiable(guesses),
        revealed: revealed ?? this.revealed,
        gaveUp: gaveUp ?? this.gaveUp,
      );

  @override
  List<Object?> get props => [puzzle, guesses, revealed, gaveUp];
}
