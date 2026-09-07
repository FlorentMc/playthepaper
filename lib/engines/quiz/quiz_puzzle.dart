import 'package:equatable/equatable.dart';

/// One quiz question: a prompt, four options and the story it came from.
class QuizQuestion extends Equatable {
  const QuizQuestion({required this.prompt, required this.options, required this.storyId});

  final String prompt;
  final List<String> options;
  final String storyId;

  Map<String, dynamic> toJson() => {'prompt': prompt, 'options': options, 'storyId': storyId};

  @override
  List<Object?> get props => [prompt, options, storyId];
}

/// The Quiz: five questions from the day's stories and one wager. Parsed from
/// the record's payload (questions) and reveal (answers and explanations).
class QuizPuzzle extends Equatable {
  const QuizPuzzle._({
    required this.questions,
    required this.wagerQuestion,
    required this.answers,
    required this.explanations,
  });

  static const int questionCount = 5;
  static const int optionCount = 4;
  static const int defaultWagerQuestion = 4;

  final List<QuizQuestion> questions;

  /// Index of the question the player may stake a point on.
  final int wagerQuestion;

  /// Index of the correct option, per question.
  final List<int> answers;
  final List<String> explanations;

  /// Five correct answers plus the wager bonus.
  int get maxPoints => questions.length + 1;

  int answerOf(int i) => answers[i];

  String explanationOf(int i) => explanations[i];

  static QuizPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawQuestions = payload['questions'];
    if (rawQuestions is! List || rawQuestions.length != questionCount) {
      throw const FormatException('Quiz payload needs exactly $questionCount "questions"');
    }
    final questions = [for (var i = 0; i < rawQuestions.length; i++) _parseQuestion(rawQuestions[i], i + 1)];

    final rawWager = payload['wagerQuestion'] ?? defaultWagerQuestion;
    if (rawWager is! int || rawWager < 0 || rawWager >= questionCount) {
      throw const FormatException('Quiz "wagerQuestion" must be an index from 0 to ${questionCount - 1}');
    }

    final rawAnswers = reveal['answers'];
    if (rawAnswers is! List || rawAnswers.length != questionCount) {
      throw const FormatException('Quiz reveal needs exactly $questionCount "answers"');
    }
    final answers = <int>[];
    for (final a in rawAnswers) {
      if (a is! int || a < 0 || a >= optionCount) {
        throw FormatException('Quiz answer must be an option index from 0 to ${optionCount - 1}, not $a');
      }
      answers.add(a);
    }

    final rawExplanations = reveal['explanations'];
    if (rawExplanations is! List || rawExplanations.length != questionCount) {
      throw const FormatException('Quiz reveal needs exactly $questionCount "explanations"');
    }
    final explanations = <String>[];
    for (var i = 0; i < rawExplanations.length; i++) {
      final e = rawExplanations[i];
      if (e is! String || e.trim().isEmpty) {
        throw FormatException('Quiz explanation ${i + 1} must be a non-empty string');
      }
      explanations.add(e);
    }

    return QuizPuzzle._(
      questions: List.unmodifiable(questions),
      wagerQuestion: rawWager,
      answers: List.unmodifiable(answers),
      explanations: List.unmodifiable(explanations),
    );
  }

  static QuizQuestion _parseQuestion(Object? raw, int number) {
    if (raw is! Map) throw FormatException('Quiz question $number must be an object');
    final prompt = raw['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      throw FormatException('Quiz question $number needs a non-empty "prompt"');
    }
    final rawOptions = raw['options'];
    if (rawOptions is! List || rawOptions.length != optionCount) {
      throw FormatException('Quiz question $number needs exactly $optionCount "options"');
    }
    final options = <String>[];
    for (final o in rawOptions) {
      if (o is! String || o.trim().isEmpty) {
        throw FormatException('Quiz question $number has an empty option');
      }
      options.add(o);
    }
    if (options.toSet().length != options.length) {
      throw FormatException('Quiz question $number has repeated options');
    }
    final storyId = raw['storyId'];
    if (storyId is! String || storyId.trim().isEmpty) {
      throw FormatException('Quiz question $number needs a non-empty "storyId"');
    }
    return QuizQuestion(prompt: prompt, options: List.unmodifiable(options), storyId: storyId);
  }

  Map<String, dynamic> toPayload() => {
        'questions': questions.map((q) => q.toJson()).toList(),
        'wagerQuestion': wagerQuestion,
      };

  Map<String, dynamic> toReveal() => {'answers': answers, 'explanations': explanations};

  @override
  List<Object?> get props => [questions, wagerQuestion, answers, explanations];
}
