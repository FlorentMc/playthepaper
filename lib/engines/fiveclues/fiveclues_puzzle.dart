import 'package:equatable/equatable.dart';

import 'fiveclues_text.dart';

/// Five Clues: five written clues that all point at one answer, shown one at
/// a time, hardest first. Guessing early is worth more.
///
/// Payload: `{"clues": ["...", "...", "...", "...", "..."]}` in the order the
/// player sees them. Reveal: `{"answer": "Honey", "aliases": ["runny honey"],
/// "explanations": ["...", ×5]}`, one explanation per clue.
///
/// [parse] rejects: any shape error; a clue list that is not exactly
/// [clueCount] non-empty strings; a clue outside [minClueLength] to
/// [maxClueLength] characters; two clues that normalise the same; an answer
/// with no letters or digits; an alias that repeats the answer or another
/// alias; explanations that are not one per clue, or that are shorter than
/// [minExplanationLength], or that repeat the clue they explain; and any
/// clue that contains the answer or one of its aliases, which would hand the
/// answer over. The reveal is also checked against the matcher: the answer
/// and every alias must be accepted by [accepts].
class FiveCluesPuzzle extends Equatable {
  const FiveCluesPuzzle._({
    required this.clues,
    required this.answer,
    required this.aliases,
    required this.explanations,
    required this.accepted,
  });

  /// Clues per puzzle, and the score for solving on the first one.
  static const int clueCount = 5;
  static const int maxPoints = clueCount;
  static const int minClueLength = 8;
  static const int maxClueLength = 120;
  static const int minExplanationLength = 20;

  /// The clues in the order they are shown, hardest first.
  final List<String> clues;

  /// The answer as it is written on the reveal.
  final String answer;

  /// Other spellings and short forms that are also accepted.
  final List<String> aliases;

  /// One explanation per clue, in the same order.
  final List<String> explanations;

  /// Normalised forms that solve the puzzle: the answer and every alias.
  final Set<String> accepted;

  /// The score for solving while clue [index] is the newest one shown:
  /// [clueCount] on the first clue down to 1 on the last.
  static int pointsForClue(int index) => clueCount - index;

  /// True when [raw] names the answer, by any accepted spelling.
  bool accepts(String raw) => accepted.contains(FiveCluesText.normalise(raw));

  static FiveCluesPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawClues = payload['clues'];
    if (rawClues is! List || rawClues.length != clueCount) {
      throw const FormatException('Five Clues payload needs exactly $clueCount "clues"');
    }
    final clues = <String>[];
    final seen = <String>{};
    for (var i = 0; i < rawClues.length; i++) {
      final clue = rawClues[i];
      if (clue is! String || clue.trim().isEmpty) {
        throw FormatException('Five Clues clue ${i + 1} must be a non-empty string');
      }
      final text = clue.trim();
      if (text.length < minClueLength || text.length > maxClueLength) {
        throw FormatException(
          'Five Clues clue ${i + 1} is ${text.length} characters; expected $minClueLength to $maxClueLength',
        );
      }
      if (!seen.add(FiveCluesText.normalise(text))) {
        throw FormatException('Five Clues clue ${i + 1} repeats an earlier clue');
      }
      clues.add(text);
    }

    final rawAnswer = reveal['answer'];
    if (rawAnswer is! String || rawAnswer.trim().isEmpty) {
      throw const FormatException('Five Clues reveal needs an "answer"');
    }
    final answer = rawAnswer.trim();
    final normalisedAnswer = FiveCluesText.normalise(answer);
    if (normalisedAnswer.isEmpty) {
      throw FormatException('Five Clues answer "$answer" has no letters or digits');
    }

    final aliases = _strings(reveal['aliases'], 'aliases', allowMissing: true);
    final accepted = <String>{normalisedAnswer};
    for (final alias in aliases) {
      final normalised = FiveCluesText.normalise(alias);
      if (normalised.isEmpty) throw FormatException('Five Clues alias "$alias" has no letters or digits');
      if (!accepted.add(normalised)) {
        throw FormatException('Five Clues alias "$alias" repeats the answer or another alias');
      }
    }

    final explanations = _strings(reveal['explanations'], 'explanations', allowMissing: false);
    if (explanations.length != clueCount) {
      throw FormatException('Five Clues reveal needs $clueCount "explanations", one per clue');
    }
    for (var i = 0; i < explanations.length; i++) {
      if (explanations[i].trim().length < minExplanationLength) {
        throw FormatException('Five Clues explanation ${i + 1} is too short to explain the link');
      }
      if (FiveCluesText.normalise(explanations[i]) == FiveCluesText.normalise(clues[i])) {
        throw FormatException('Five Clues explanation ${i + 1} only repeats its clue');
      }
    }

    for (var i = 0; i < clues.length; i++) {
      for (final phrase in [answer, ...aliases]) {
        if (FiveCluesText.containsPhrase(clues[i], phrase)) {
          throw FormatException('Five Clues clue ${i + 1} gives the answer away');
        }
      }
    }

    final puzzle = FiveCluesPuzzle._(
      clues: List.unmodifiable(clues),
      answer: answer,
      aliases: List.unmodifiable(aliases),
      explanations: List.unmodifiable(explanations.map((e) => e.trim())),
      accepted: Set.unmodifiable(accepted),
    );
    for (final phrase in [answer, ...aliases]) {
      if (!puzzle.accepts(phrase)) {
        throw FormatException('Five Clues would not accept its own answer "$phrase"');
      }
    }
    return puzzle;
  }

  static List<String> _strings(Object? value, String field, {required bool allowMissing}) {
    if (value == null && allowMissing) return const [];
    if (value is! List) throw FormatException('Five Clues reveal "$field" must be a list of strings');
    final out = <String>[];
    for (final v in value) {
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('Five Clues reveal "$field" must hold non-empty strings');
      }
      out.add(v.trim());
    }
    return out;
  }

  Map<String, dynamic> toPayload() => {'clues': clues};

  Map<String, dynamic> toReveal() => {
        'answer': answer,
        if (aliases.isNotEmpty) 'aliases': aliases,
        'explanations': explanations,
      };

  @override
  List<Object?> get props => [clues, answer, aliases, explanations];
}
