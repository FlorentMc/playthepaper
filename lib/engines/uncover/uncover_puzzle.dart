import 'uncover_text.dart';

/// What a word of the text is to the player.
enum UncoverWordKind {
  /// Spaces and punctuation, always shown.
  separator,

  /// A common word, shown from the start.
  common,

  /// Hidden until the player guesses it.
  hidden,

  /// Part of the subject's name; shown only when the puzzle ends.
  subject,
}

/// One token of the reveal text, classified.
class UncoverWord {
  const UncoverWord({required this.text, required this.normalised, required this.kind});

  final String text;
  final String normalised;
  final UncoverWordKind kind;

  bool get isSubject => kind == UncoverWordKind.subject;
  bool get isHidden => kind == UncoverWordKind.hidden;
  bool get isSeparator => kind == UncoverWordKind.separator;
}

/// A validated hidden-story puzzle.
///
/// Payload: `{"text": "the summary with every subject word as ▇▇▇", "hints": ["...", "...", "..."]}`.
/// Reveal: `{"text": "the summary", "subject": "Angel Falls",
///          "aliases": ["kerepakupai meru"], "answerWords": ["angel", "falls"]}`.
///
/// Rules, each checked by [parse]:
///
/// * the reveal text has [minWords] to [maxWords] words and no mask characters;
/// * the subject is not empty and `answerWords` are exactly its words that
///   are not common words (normalised), at least one;
/// * every occurrence of the subject or an alias as a phrase, and every
///   standalone occurrence of an answer word, is a subject word; the payload
///   text is the reveal text with each subject word replaced by [UncoverText.mask];
/// * the subject appears at least once and at least [minHiddenWords] other
///   words are left to guess;
/// * up to three hints, none containing an answer word or the subject.
class UncoverPuzzle {
  const UncoverPuzzle._({
    required this.maskedText,
    required this.text,
    required this.hints,
    required this.subject,
    required this.aliases,
    required this.answerWords,
    required this.words,
    required this.acceptedAnswers,
  });

  static const int minWords = 60;
  static const int maxWords = 200;
  static const int minHiddenWords = 25;
  static const int maxHints = 3;

  /// The payload text, subject words masked.
  final String maskedText;

  /// The reveal text.
  final String text;
  final List<String> hints;
  final String subject;
  final List<String> aliases;
  final List<String> answerWords;

  /// The reveal text as classified tokens.
  final List<UncoverWord> words;

  /// Normalised phrases that solve the puzzle: the subject and every alias.
  final Set<String> acceptedAnswers;

  int get wordCount => words.where((w) => !w.isSeparator).length;
  int get hiddenCount => words.where((w) => w.isHidden).length;
  int get subjectCount => words.where((w) => w.isSubject).length;

  /// True when [raw] names the subject, by any accepted alias.
  bool isAnswer(String raw) => acceptedAnswers.contains(UncoverText.normalisePhrase(raw));

  /// Occurrences of a normalised word among the guessable words.
  int occurrences(String normalised) =>
      normalised.isEmpty ? 0 : words.where((w) => w.isHidden && w.normalised == normalised).length;

  static UncoverPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final maskedText = _text(payload['text'], 'payload "text"');
    final hints = _strings(payload['hints'], 'payload "hints"', allowMissing: true);
    if (hints.length > maxHints) throw const FormatException('Uncover payload has more than $maxHints hints');
    final text = _text(reveal['text'], 'reveal "text"');
    final subject = _text(reveal['subject'], 'reveal "subject"');
    final aliases = _strings(reveal['aliases'], 'reveal "aliases"', allowMissing: true);
    final answerWords = _strings(reveal['answerWords'], 'reveal "answerWords"', allowMissing: false);

    final expectedAnswers = answerWordsFor(subject).toSet();
    final givenAnswers = answerWords.map(UncoverText.normaliseWord).toSet();
    if (givenAnswers.length != expectedAnswers.length || !givenAnswers.containsAll(expectedAnswers)) {
      throw FormatException(
        'Uncover reveal "answerWords" must be the subject\'s words that are not common: ${expectedAnswers.join(', ')}',
      );
    }
    final accepted = {UncoverText.normalisePhrase(subject), ...aliases.map(UncoverText.normalisePhrase)};

    final words = classifyReveal(text: text, subject: subject, aliases: aliases);
    final count = words.where((w) => !w.isSeparator).length;
    if (count < minWords || count > maxWords) {
      throw FormatException('Uncover text has $count words; expected $minWords to $maxWords');
    }
    if (!words.any((w) => w.isSubject)) throw const FormatException('Uncover subject never appears in the text');
    final hidden = words.where((w) => w.isHidden).length;
    if (hidden < minHiddenWords) {
      throw FormatException('Uncover text leaves only $hidden words to guess; expected at least $minHiddenWords');
    }
    if (maskedText != render(words)) {
      throw const FormatException('Uncover payload "text" is not the reveal text with the subject masked');
    }

    for (final hint in hints) {
      final hintWords = _phraseWords(hint);
      if (hintWords.any(expectedAnswers.contains)) {
        throw FormatException('Uncover hint gives away an answer word: "$hint"');
      }
      final phrase = hintWords.join(' ');
      if (accepted.any((a) => a.length > 1 && phrase.contains(a))) {
        throw FormatException('Uncover hint gives away the subject: "$hint"');
      }
    }

    return UncoverPuzzle._(
      maskedText: maskedText,
      text: text,
      hints: List.unmodifiable(hints),
      subject: subject,
      aliases: List.unmodifiable(aliases),
      answerWords: List.unmodifiable(answerWords),
      words: List.unmodifiable(words),
      acceptedAnswers: Set.unmodifiable(accepted),
    );
  }

  /// The normalised words of [subject] that are not common words: what the
  /// reveal must list as `answerWords`. Throws when none remain.
  static List<String> answerWordsFor(String subject) {
    final words = _phraseWords(subject);
    if (words.isEmpty) throw const FormatException('Uncover reveal "subject" has no letters');
    final answers = words.where((w) => !UncoverText.isCommon(w)).toSet().toList();
    if (answers.isEmpty) throw const FormatException('Uncover reveal "subject" is made only of common words');
    return answers;
  }

  /// Classifies the reveal [text] for [subject] and its [aliases].
  static List<UncoverWord> classifyReveal({
    required String text,
    required String subject,
    required List<String> aliases,
  }) {
    if (text.contains('▇')) throw const FormatException('Uncover reveal "text" must not contain the mask character');
    final phrases = <List<String>>[_phraseWords(subject)];
    for (final alias in aliases) {
      final aliasWords = _phraseWords(alias);
      if (aliasWords.isEmpty) throw FormatException('Uncover alias "$alias" has no letters');
      if (aliasWords.every(UncoverText.isCommon)) {
        throw FormatException('Uncover alias "$alias" is made only of common words');
      }
      phrases.add(aliasWords);
    }
    return classify(text, phrases: phrases, answerWords: answerWordsFor(subject).toSet());
  }

  /// The payload text for a reveal: the reveal text with every subject word
  /// masked. For editors preparing a news item.
  static String maskedTextFor(Map<String, dynamic> reveal) => render(classifyReveal(
        text: _text(reveal['text'], 'reveal "text"'),
        subject: _text(reveal['subject'], 'reveal "subject"'),
        aliases: _strings(reveal['aliases'], 'reveal "aliases"', allowMissing: true),
      ));

  /// Classifies every token of [text]: subject words are the tokens covered
  /// by an occurrence of one of [phrases] (normalised word lists, adjacent
  /// in the text) or equal to one of [answerWords]; common words are shown;
  /// everything else is hidden.
  static List<UncoverWord> classify(
    String text, {
    required List<List<String>> phrases,
    required Set<String> answerWords,
  }) {
    final tokens = UncoverText.tokenise(text);
    final subject = List<bool>.filled(tokens.length, false);
    for (var i = 0; i < tokens.length; i++) {
      if (!tokens[i].isWord) continue;
      if (answerWords.contains(tokens[i].normalised)) subject[i] = true;
      for (final phrase in phrases) {
        final end = _matchPhrase(tokens, i, phrase);
        if (end == null) continue;
        for (var j = i; j < end; j++) {
          if (tokens[j].isWord) subject[j] = true;
        }
      }
    }
    return [
      for (var i = 0; i < tokens.length; i++)
        UncoverWord(
          text: tokens[i].text,
          normalised: tokens[i].normalised,
          kind: switch (tokens[i].kind) {
            UncoverTokenKind.separator => UncoverWordKind.separator,
            UncoverTokenKind.mask => UncoverWordKind.subject,
            UncoverTokenKind.word => subject[i]
                ? UncoverWordKind.subject
                : UncoverText.isCommon(tokens[i].normalised)
                    ? UncoverWordKind.common
                    : UncoverWordKind.hidden,
          },
        ),
    ];
  }

  /// The payload text for [words]: every subject word replaced by the mask.
  static String render(List<UncoverWord> words) =>
      words.map((w) => w.isSubject ? UncoverText.mask : w.text).join();

  /// Returns the index after the last token of [phrase] when it starts at
  /// token [start], or null.
  static int? _matchPhrase(List<UncoverToken> tokens, int start, List<String> phrase) {
    var i = start;
    for (var p = 0; p < phrase.length; p++) {
      if (p > 0) {
        if (i < tokens.length && tokens[i].kind == UncoverTokenKind.separator) {
          if (!UncoverText.joinsPhrase(tokens[i].text)) return null;
          i++;
        }
      }
      if (i >= tokens.length || !tokens[i].isWord || tokens[i].normalised != phrase[p]) return null;
      i++;
    }
    return i;
  }

  static List<String> _phraseWords(String phrase) =>
      UncoverText.normalisePhrase(phrase).split(' ').where((w) => w.isNotEmpty).toList();

  static String _text(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) throw FormatException('Uncover $field must be a non-empty string');
    return value;
  }

  static List<String> _strings(Object? value, String field, {required bool allowMissing}) {
    if (value == null && allowMissing) return const [];
    if (value is! List) throw FormatException('Uncover $field must be a list of strings');
    final out = <String>[];
    for (final v in value) {
      if (v is! String || v.trim().isEmpty) throw FormatException('Uncover $field must be a list of non-empty strings');
      out.add(v);
    }
    return out;
  }

  Map<String, dynamic> toPayload() => {'text': maskedText, if (hints.isNotEmpty) 'hints': hints};

  Map<String, dynamic> toReveal() => {
        'text': text,
        'subject': subject,
        'aliases': aliases,
        'answerWords': answerWords,
      };
}
