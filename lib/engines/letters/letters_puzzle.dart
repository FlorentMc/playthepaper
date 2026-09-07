/// Points for an accepted [word] built from the seven puzzle [letters]:
/// four letters score 1, longer words score their length, and a pangram
/// (one that uses every letter) earns 7 more.
int scoreWord(String word, {required Set<String> letters}) {
  final base = word.length <= 4 ? 1 : word.length;
  return isPangram(word, letters: letters) ? base + 7 : base;
}

/// True when [word] contains every letter in [letters].
bool isPangram(String word, {required Set<String> letters}) {
  for (final letter in letters) {
    if (!word.contains(letter)) return false;
  }
  return true;
}

final RegExp _upperWord = RegExp(r'^[A-Z]+$');

/// One Letters puzzle: the seven letters and the frozen list of accepted
/// words. Parsed from a puzzle record's payload and reveal.
class LettersPuzzle {
  LettersPuzzle._({
    required this.center,
    required this.outer,
    required this.minLength,
    required List<String> answers,
    required List<String> pangrams,
    required this.maxScore,
  }) : answers = List.unmodifiable(answers),
       pangrams = List.unmodifiable(pangrams),
       letters = Set.unmodifiable({center, ...outer.split('')}),
       _answerSet = Set.unmodifiable(answers);

  /// The compulsory letter.
  final String center;

  /// The six other letters, as published.
  final String outer;
  final int minLength;

  /// Every accepted word, uppercase.
  final List<String> answers;

  /// The answers that use all seven letters.
  final List<String> pangrams;

  /// The sum of [score] over [answers].
  final int maxScore;

  /// All seven letters.
  final Set<String> letters;

  final Set<String> _answerSet;

  int get answerCount => answers.length;

  bool contains(String word) => _answerSet.contains(word);

  bool isPangramWord(String word) => isPangram(word, letters: letters);

  int score(String word) => scoreWord(word, letters: letters);

  /// Validates and parses a puzzle. Throws [FormatException] on any violation.
  static LettersPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final center = payload['center'];
    if (center is! String || center.length != 1 || !_upperWord.hasMatch(center)) {
      throw const FormatException('Letters payload needs a single uppercase "center" letter');
    }
    final outer = payload['outer'];
    if (outer is! String || outer.length != 6 || !_upperWord.hasMatch(outer)) {
      throw const FormatException('Letters payload needs six uppercase "outer" letters');
    }
    if (outer.split('').toSet().length != 6) {
      throw FormatException('Outer letters must be distinct: $outer');
    }
    if (outer.contains(center)) {
      throw FormatException('Centre letter $center must not appear in outer letters $outer');
    }
    final minLength = payload['minLength'];
    if (minLength is! int || minLength < 1) {
      throw const FormatException('Letters payload needs a positive "minLength"');
    }

    final letters = {center, ...outer.split('')};
    final answers = _stringList(reveal['answers'], 'answers');
    if (answers.isEmpty) throw const FormatException('Letters reveal has no answers');
    final seen = <String>{};
    for (final word in answers) {
      if (!_upperWord.hasMatch(word)) throw FormatException('Answer is not uppercase letters: "$word"');
      if (word.length < minLength) throw FormatException('Answer shorter than $minLength: $word');
      if (!word.contains(center)) throw FormatException('Answer missing centre letter $center: $word');
      for (final ch in word.split('')) {
        if (!letters.contains(ch)) throw FormatException('Answer uses letter $ch outside the puzzle: $word');
      }
      if (!seen.add(word)) throw FormatException('Duplicate answer: $word');
    }

    final pangrams = _stringList(reveal['pangrams'], 'pangrams');
    final pangramSet = <String>{};
    for (final word in pangrams) {
      if (!seen.contains(word)) throw FormatException('Pangram not in answers: $word');
      if (!isPangram(word, letters: letters)) throw FormatException('Listed pangram does not use every letter: $word');
      if (!pangramSet.add(word)) throw FormatException('Duplicate pangram: $word');
    }
    var sum = 0;
    for (final word in answers) {
      if (isPangram(word, letters: letters) && !pangramSet.contains(word)) {
        throw FormatException('Answer uses every letter but is not listed as a pangram: $word');
      }
      sum += scoreWord(word, letters: letters);
    }

    final maxScore = reveal['maxScore'];
    if (maxScore is! int) throw const FormatException('Letters reveal needs an integer "maxScore"');
    if (maxScore != sum) throw FormatException('maxScore is $maxScore but the answers total $sum');

    return LettersPuzzle._(
      center: center,
      outer: outer,
      minLength: minLength,
      answers: answers,
      pangrams: pangrams,
      maxScore: maxScore,
    );
  }

  static List<String> _stringList(Object? raw, String field) {
    if (raw is! List) throw FormatException('Letters reveal needs a "$field" list');
    return raw.map((w) {
      if (w is! String) throw FormatException('Non-string entry in "$field": $w');
      return w;
    }).toList();
  }
}
