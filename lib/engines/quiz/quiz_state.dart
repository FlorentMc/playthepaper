import 'package:equatable/equatable.dart';

import 'quiz_puzzle.dart';

/// The answers given so far and whether the wager is staked. Immutable:
/// every transition returns a new state. Points are derived, never stored.
class QuizState extends Equatable {
  const QuizState._({required this.puzzle, required this.answers, required this.staked});

  QuizState.initial(QuizPuzzle puzzle)
      : this._(
          puzzle: puzzle,
          answers: List<int?>.unmodifiable(List<int?>.filled(puzzle.questions.length, null)),
          staked: false,
        );

  final QuizPuzzle puzzle;

  /// The chosen option per question, null until answered. Questions are
  /// answered in order.
  final List<int?> answers;

  /// True when a point is staked on the wager question.
  final bool staked;

  /// Index of the first unanswered question, or the question count once
  /// every question is answered.
  int get current {
    final i = answers.indexWhere((a) => a == null);
    return i < 0 ? answers.length : i;
  }

  bool get isFinished => current == answers.length;

  bool isAnswered(int i) => answers[i] != null;

  bool isCorrect(int i) {
    final a = answers[i];
    return a != null && a == puzzle.answerOf(i);
  }

  bool isWager(int i) => i == puzzle.wagerQuestion;

  /// Points a question has earned: 1 when right, 0 when wrong or unanswered.
  /// A staked wager scores 2 when right and -1 when wrong.
  int pointsFor(int i) {
    if (!isAnswered(i)) return 0;
    if (staked && isWager(i)) return isCorrect(i) ? 2 : -1;
    return isCorrect(i) ? 1 : 0;
  }

  int get points {
    var total = 0;
    for (var i = 0; i < answers.length; i++) {
      total += pointsFor(i);
    }
    return total < 0 ? 0 : total;
  }

  /// The wager is offered only at the wager question, before it is answered,
  /// to a player with at least one point to stake.
  bool get canStake => current == puzzle.wagerQuestion && points >= 1;

  /// Answers the current question. Ignored once every question is answered.
  QuizState answer(int option) {
    if (isFinished) return this;
    if (option < 0 || option >= QuizPuzzle.optionCount) {
      throw ArgumentError('Option $option is not between 0 and ${QuizPuzzle.optionCount - 1}');
    }
    final next = List<int?>.of(answers);
    next[current] = option;
    return QuizState._(puzzle: puzzle, answers: List.unmodifiable(next), staked: staked);
  }

  QuizState stake() => canStake && !staked ? QuizState._(puzzle: puzzle, answers: answers, staked: true) : this;

  QuizState unstake() =>
      staked && current == puzzle.wagerQuestion ? QuizState._(puzzle: puzzle, answers: answers, staked: false) : this;

  /// One spoiler-free row: 🟩 or 🟥 per question, with ⭐ before the wager
  /// mark when staked.
  String shareLine() {
    final buffer = StringBuffer();
    for (var i = 0; i < answers.length; i++) {
      if (staked && isWager(i)) buffer.write('⭐');
      buffer.write(!isAnswered(i)
          ? '⬜'
          : isCorrect(i)
              ? '🟩'
              : '🟥');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {'answers': answers, 'staked': staked};

  /// Rebuilds a state from [toJson] by replaying it. Throws [FormatException]
  /// when the saved progress could not have been reached in [puzzle].
  static QuizState fromJson(QuizPuzzle puzzle, Map<String, dynamic> json) {
    final raw = json['answers'];
    if (raw is! List || raw.length != puzzle.questions.length) {
      throw FormatException('Quiz progress needs ${puzzle.questions.length} "answers"');
    }
    final staked = json['staked'] ?? false;
    if (staked is! bool) throw const FormatException('Quiz progress needs a boolean "staked"');

    var state = QuizState.initial(puzzle);
    for (var i = 0; i < raw.length; i++) {
      if (staked && puzzle.wagerQuestion == i) {
        state = state.stake();
        if (!state.staked) throw const FormatException('Quiz progress stakes a point the player did not have');
      }
      final a = raw[i];
      if (a == null) {
        if (raw.skip(i).any((x) => x != null)) {
          throw const FormatException('Quiz progress skips a question');
        }
        break;
      }
      if (a is! int || a < 0 || a >= QuizPuzzle.optionCount) {
        throw FormatException('Quiz progress has an invalid answer: $a');
      }
      state = state.answer(a);
    }
    if (state.staked != staked) throw const FormatException('Quiz progress stakes before the wager question');
    return state;
  }

  @override
  List<Object?> get props => [puzzle, answers, staked];
}
