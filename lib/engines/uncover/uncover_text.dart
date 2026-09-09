/// Text rules shared by the parser, the state and the screen: how a text is
/// cut into words, how a word is normalised for matching, and which words
/// are common enough to be shown from the start.
///
/// Normalisation of a single word, in this order:
///
///   1. lower-case;
///   2. ASCII-fold accented letters (`Merú` → `meru`, `façade` → `facade`);
///   3. drop a possessive `'s` or `’s`;
///   4. drop every character that is not a–z or 0–9;
///   5. strip a plural ending: `-ies` → `-y` when the word has five or more
///      letters (`cities` → `city`, but `ties` → `tie` by the next rule),
///      `-es` after `s`, `x`, `z`, `ch` or `sh` when the stem keeps at least
///      three letters (`branches` → `branch`), otherwise a final `s` that
///      does not follow another `s`, when the stem keeps at least three
///      letters (`falls` → `fall`, `glass` and `bus` unchanged).
///
/// A phrase (a guess at the subject) is normalised word by word with the
/// same rules, a leading `the` is dropped, and the words are joined by one
/// space.
class UncoverText {
  UncoverText._();

  /// The mask written in a payload for every hidden word of the subject.
  static const String mask = '▇▇▇';

  static final RegExp _wordPattern = RegExp(
    r"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*(?:[.,]\p{N}+)*|▇+",
    unicode: true,
  );

  static const Map<String, String> _folds = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
    'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
    'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i',
    'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'œ': 'oe',
    'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
    'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ž': 'z', 'ż': 'z',
  };

  /// Words shown from the start: articles, prepositions, conjunctions,
  /// pronouns, auxiliaries and a handful of very frequent adverbs.
  static const Set<String> commonWords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'nor', 'so', 'yet', 'if', 'than', 'then', 'as',
    'of', 'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from', 'into', 'onto', 'over', 'under',
    'up', 'down', 'out', 'off', 'about', 'above', 'below', 'between', 'among', 'through', 'during',
    'before', 'after', 'since', 'until', 'while', 'because', 'although', 'though', 'across', 'along',
    'around', 'against', 'within', 'without', 'toward', 'towards', 'near', 'per',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
    'have', 'has', 'had', 'having', 'do', 'does', 'did', 'done',
    'can', 'could', 'may', 'might', 'must', 'shall', 'should', 'will', 'would',
    'it', 'its', 'this', 'that', 'these', 'those', 'they', 'them', 'their', 'theirs', 'there',
    'he', 'she', 'his', 'her', 'hers', 'him', 'we', 'us', 'our', 'ours', 'you', 'your', 'yours',
    'i', 'me', 'my', 'mine', 'who', 'whom', 'whose', 'which', 'what', 'when', 'where', 'why', 'how',
    'not', 'no', 'also', 'only', 'just', 'very', 'too', 'more', 'most', 'much', 'many', 'some', 'any',
    'each', 'every', 'all', 'both', 'few', 'other', 'another', 'such', 'same', 'own', 'one', 'still',
    'often', 'once', 'again', 'ever', 'never', 'now', 'here', 'well', 'even', 'rather', 'itself',
    'themselves', 'himself', 'herself', 'ourselves', 'yourself',
  };

  static final Set<String> _commonNormalised = commonWords.map(normaliseWord).toSet();

  /// True when [normalised] is a common word, shown from the start.
  static bool isCommon(String normalised) => _commonNormalised.contains(normalised);

  /// Lower-cases and replaces accented letters with their ASCII base.
  static String foldAscii(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_folds[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// See the class comment for the rules. Returns the empty string for a
  /// word with no letters or digits.
  static String normaliseWord(String raw) {
    var w = foldAscii(raw.trim());
    if (w.endsWith("'s") || w.endsWith('’s')) w = w.substring(0, w.length - 2);
    w = w.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _singular(w);
  }

  static String _singular(String w) {
    if (w.length >= 5 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length >= 5 &&
        w.endsWith('es') &&
        (w.endsWith('ses') || w.endsWith('xes') || w.endsWith('zes') || w.endsWith('ches') || w.endsWith('shes'))) {
      return w.substring(0, w.length - 2);
    }
    if (w.length >= 4 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  /// Normalises a guess at the subject: every word by [normaliseWord], a
  /// leading `the` dropped, words joined by one space.
  static String normalisePhrase(String raw) {
    final words = raw
        .split(RegExp(r'[\s\-–—/]+'))
        .map(normaliseWord)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length > 1 && words.first == 'the') words.removeAt(0);
    return words.join(' ');
  }

  /// Cuts [text] into alternating separators and words. Every character of
  /// the input lands in exactly one token, so joining the tokens restores it.
  static List<UncoverToken> tokenise(String text) {
    final tokens = <UncoverToken>[];
    var last = 0;
    for (final m in _wordPattern.allMatches(text)) {
      if (m.start > last) tokens.add(UncoverToken.separator(text.substring(last, m.start)));
      final word = m[0]!;
      tokens.add(word.startsWith('▇') ? UncoverToken.mask(word) : UncoverToken.word(word));
      last = m.end;
    }
    if (last < text.length) tokens.add(UncoverToken.separator(text.substring(last)));
    return tokens;
  }

  /// True when the gap between two words of a phrase is plain spacing or a
  /// hyphen, so the words still read as one name.
  static bool joinsPhrase(String separator) => RegExp(r'^[\s\-–—]+$').hasMatch(separator);
}

enum UncoverTokenKind { separator, word, mask }

/// One piece of a text: a separator (spaces and punctuation), a word, or a
/// mask run from a payload.
class UncoverToken {
  const UncoverToken._(this.text, this.kind, this.normalised);

  factory UncoverToken.separator(String text) => UncoverToken._(text, UncoverTokenKind.separator, '');
  factory UncoverToken.word(String text) => UncoverToken._(text, UncoverTokenKind.word, UncoverText.normaliseWord(text));
  factory UncoverToken.mask(String text) => UncoverToken._(text, UncoverTokenKind.mask, '');

  final String text;
  final UncoverTokenKind kind;

  /// The matching key of a word token; empty for separators and masks.
  final String normalised;

  bool get isWord => kind == UncoverTokenKind.word;
}
