import 'package:equatable/equatable.dart';

import 'linked_text.dart';

/// One small set: two clues pointing at one answer, with a hint held back.
class LinkedSet extends Equatable {
  const LinkedSet({required this.clues, required this.answer, required this.aliases, required this.hint});

  final List<String> clues;
  final String answer;
  final List<String> aliases;

  /// The extra help, written by the editor or worked out from the answer.
  final String hint;

  @override
  List<Object?> get props => [clues, answer, aliases, hint];
}

/// Linked Clues: three small sets of two clues each lead to three answers,
/// and the three answers together lead to one final subject.
///
/// Payload: `{"sets": [{"clues": ["...", "..."], "hint": "optional"}, ×3],
/// "finalHint": "optional"}`. Reveal: `{"answers": [3 strings],
/// "aliases": [[...], [...], [...]], "final": "...", "finalAliases": [...],
/// "explanations": [4 strings]}` — one explanation per set, then one for the
/// link that ties the three answers to the final subject.
///
/// A hint the content does not supply is worked out from the answer with
/// [shapeHint]: its first letter and the length of each word.
///
/// [parse] rejects: any shape error; a number of sets, clues or explanations
/// other than [setCount], [cluesPerSet] and `setCount + 1`; a clue or hint
/// outside [minClueLength] to [maxClueLength] characters; two clues that
/// normalise the same; an answer or final subject with no letters or digits;
/// two answers that mean the same, or an answer that repeats the final; an
/// alias that repeats another accepted form, in its own set or in another;
/// an explanation shorter than [minExplanationLength]; and any clue or hint
/// that contains one of the answers or the final subject, which would give
/// the game away. The reveal is checked against the matcher too: every
/// answer and alias must be accepted where it belongs.
class LinkedPuzzle extends Equatable {
  const LinkedPuzzle._({
    required this.sets,
    required this.finalAnswer,
    required this.finalAliases,
    required this.finalHint,
    required this.explanations,
    required this.acceptedBySet,
    required this.acceptedFinal,
  });

  static const int setCount = 3;
  static const int cluesPerSet = 2;
  static const int maxPoints = 10;
  static const int minPointsWhenSolved = 1;
  static const int minClueLength = 8;
  static const int maxClueLength = 120;
  static const int minExplanationLength = 20;

  /// The three sets, in the order the player sees them.
  final List<LinkedSet> sets;

  /// The subject the three answers point at.
  final String finalAnswer;
  final List<String> finalAliases;
  final String finalHint;

  /// One explanation per set, then the link to the final subject.
  final List<String> explanations;

  /// Normalised forms accepted for each set.
  final List<Set<String>> acceptedBySet;

  /// Normalised forms accepted for the final subject.
  final Set<String> acceptedFinal;

  String get linkExplanation => explanations.last;

  /// True when [raw] answers set [index].
  bool acceptsAt(int index, String raw) => acceptedBySet[index].contains(LinkedText.normalise(raw));

  /// True when [raw] names the final subject.
  bool acceptsFinal(String raw) => acceptedFinal.contains(LinkedText.normalise(raw));

  /// The fallback hint for an answer the content gives no hint for: the
  /// first letter and the length of each word, e.g. `Starts with R · 3
  /// letters` or `Starts with C · 5 and 4 letters`.
  static String shapeHint(String answer) {
    final words = LinkedText.words(answer);
    if (words.isEmpty) throw FormatException('Cannot describe the shape of "$answer"');
    final lengths = words.map((w) => w.length).toList();
    final counted = lengths.length == 1
        ? '${lengths.first} letters'
        : '${lengths.sublist(0, lengths.length - 1).join(', ')} and ${lengths.last} letters';
    return 'Starts with ${words.first[0].toUpperCase()} · $counted';
  }

  static LinkedPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawSets = payload['sets'];
    if (rawSets is! List || rawSets.length != setCount) {
      throw const FormatException('Linked payload needs exactly $setCount "sets"');
    }
    final answers = _strings(reveal['answers'], 'answers', allowMissing: false);
    if (answers.length != setCount) {
      throw const FormatException('Linked reveal needs $setCount "answers", one per set');
    }
    final rawAliases = reveal['aliases'];
    if (rawAliases != null && (rawAliases is! List || rawAliases.length != setCount)) {
      throw const FormatException('Linked reveal "aliases" must hold one list per set');
    }
    final aliases = <List<String>>[
      for (var i = 0; i < setCount; i++)
        rawAliases == null ? const <String>[] : _strings((rawAliases as List)[i], 'aliases', allowMissing: true),
    ];

    final finalAnswer = _text(reveal['final'], 'reveal "final"');
    final finalAliases = _strings(reveal['finalAliases'], 'finalAliases', allowMissing: true);

    final explanations = _strings(reveal['explanations'], 'explanations', allowMissing: false);
    if (explanations.length != setCount + 1) {
      throw const FormatException('Linked reveal needs ${setCount + 1} "explanations": one per set and one for the link');
    }
    for (var i = 0; i < explanations.length; i++) {
      if (explanations[i].length < minExplanationLength) {
        throw FormatException('Linked explanation ${i + 1} is too short to explain the link');
      }
    }

    // Every accepted form, across all four answers, must be distinct: a guess
    // may never be right in two places at once.
    final accepted = <Set<String>>[];
    final owner = <String, String>{};
    void claim(String phrase, String where, Set<String> into) {
      final normalised = LinkedText.normalise(phrase);
      if (normalised.isEmpty) throw FormatException('Linked answer "$phrase" has no letters or digits');
      final held = owner[normalised];
      if (held != null) throw FormatException('Linked $where repeats $held: "$phrase"');
      owner[normalised] = where;
      into.add(normalised);
    }

    for (var i = 0; i < setCount; i++) {
      final into = <String>{};
      claim(answers[i], 'answer ${i + 1}', into);
      for (final alias in aliases[i]) {
        claim(alias, 'alias of answer ${i + 1}', into);
      }
      accepted.add(Set.unmodifiable(into));
    }
    final acceptedFinal = <String>{};
    claim(finalAnswer, 'the final subject', acceptedFinal);
    for (final alias in finalAliases) {
      claim(alias, 'alias of the final subject', acceptedFinal);
    }

    final sets = <LinkedSet>[];
    final seenClues = <String>{};
    for (var i = 0; i < setCount; i++) {
      final raw = rawSets[i];
      if (raw is! Map) throw FormatException('Linked set ${i + 1} must be an object');
      final rawClues = raw['clues'];
      if (rawClues is! List || rawClues.length != cluesPerSet) {
        throw FormatException('Linked set ${i + 1} needs exactly $cluesPerSet "clues"');
      }
      final clues = <String>[];
      for (var c = 0; c < rawClues.length; c++) {
        final clue = _line(rawClues[c], 'Linked set ${i + 1} clue ${c + 1}');
        if (!seenClues.add(LinkedText.normalise(clue))) {
          throw FormatException('Linked set ${i + 1} clue ${c + 1} repeats an earlier clue');
        }
        clues.add(clue);
      }
      final rawHint = raw['hint'];
      final hint = rawHint == null ? shapeHint(answers[i]) : _line(rawHint, 'Linked set ${i + 1} hint');
      sets.add(LinkedSet(
        clues: List.unmodifiable(clues),
        answer: answers[i],
        aliases: List.unmodifiable(aliases[i]),
        hint: hint,
      ));
    }
    final rawFinalHint = payload['finalHint'];
    final finalHint = rawFinalHint == null ? shapeHint(finalAnswer) : _line(rawFinalHint, 'Linked "finalHint"');

    final givenAway = [finalAnswer, ...finalAliases, for (var i = 0; i < setCount; i++) ...[answers[i], ...aliases[i]]];
    for (var i = 0; i < setCount; i++) {
      for (final line in [...sets[i].clues, sets[i].hint]) {
        for (final phrase in givenAway) {
          if (LinkedText.containsPhrase(line, phrase)) {
            throw FormatException('Linked set ${i + 1} gives an answer away: "$line"');
          }
        }
      }
    }
    for (final phrase in givenAway) {
      if (LinkedText.containsPhrase(finalHint, phrase)) {
        throw FormatException('Linked "finalHint" gives an answer away');
      }
    }

    final puzzle = LinkedPuzzle._(
      sets: List.unmodifiable(sets),
      finalAnswer: finalAnswer,
      finalAliases: List.unmodifiable(finalAliases),
      finalHint: finalHint,
      explanations: List.unmodifiable(explanations),
      acceptedBySet: List.unmodifiable(accepted),
      acceptedFinal: Set.unmodifiable(acceptedFinal),
    );
    for (var i = 0; i < setCount; i++) {
      for (final phrase in [answers[i], ...aliases[i]]) {
        if (!puzzle.acceptsAt(i, phrase)) {
          throw FormatException('Linked would not accept its own answer "$phrase"');
        }
      }
    }
    if (!puzzle.acceptsFinal(finalAnswer)) {
      throw FormatException('Linked would not accept its own final subject "$finalAnswer"');
    }
    return puzzle;
  }

  static String _line(Object? value, String where) {
    if (value is! String || value.trim().isEmpty) throw FormatException('$where must be a non-empty string');
    final text = value.trim();
    if (text.length < minClueLength || text.length > maxClueLength) {
      throw FormatException('$where is ${text.length} characters; expected $minClueLength to $maxClueLength');
    }
    return text;
  }

  static String _text(Object? value, String where) {
    if (value is! String || value.trim().isEmpty) throw FormatException('Linked $where must be a non-empty string');
    return value.trim();
  }

  static List<String> _strings(Object? value, String field, {required bool allowMissing}) {
    if (value == null && allowMissing) return const [];
    if (value is! List) throw FormatException('Linked reveal "$field" must be a list of strings');
    final out = <String>[];
    for (final v in value) {
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('Linked reveal "$field" must hold non-empty strings');
      }
      out.add(v.trim());
    }
    return out;
  }

  Map<String, dynamic> toPayload() => {
        'sets': [
          for (final set in sets) {'clues': set.clues, 'hint': set.hint},
        ],
        'finalHint': finalHint,
      };

  Map<String, dynamic> toReveal() => {
        'answers': [for (final set in sets) set.answer],
        'aliases': [for (final set in sets) set.aliases],
        'final': finalAnswer,
        if (finalAliases.isNotEmpty) 'finalAliases': finalAliases,
        'explanations': explanations,
      };

  @override
  List<Object?> get props => [sets, finalAnswer, finalAliases, finalHint, explanations];
}
