/// How a typed guess is compared with the answer, and how a clue is checked
/// for giving the answer away. Shared by the parser, the state and the screen.
///
/// Normalisation of a phrase, in this order:
///
///   1. lower-case;
///   2. ASCII-fold accented letters (`café` → `cafe`, `Åland` → `aland`);
///   3. drop a possessive `'s` or `’s` from the end of each word;
///   4. turn every character that is not a–z or 0–9 into a space, so
///      punctuation, hyphens and slashes all read as word breaks;
///   5. collapse runs of spaces and trim;
///   6. drop a leading `the`, `a` or `an` when at least one word remains.
///
/// So `The Great Barrier Reef`, `great barrier reef` and `Great-Barrier
/// Reef!` all match. Nothing is stemmed: a plural such as `coral reefs` is
/// matched by listing it as an alias, never by guesswork.
class FiveCluesText {
  FiveCluesText._();

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

  /// Articles dropped from the front of a phrase.
  static const Set<String> leadingArticles = {'the', 'a', 'an'};

  /// Words too common to prove that a clue names the answer.
  static const Set<String> commonWords = {
    'a', 'an', 'the', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for', 'with', 'by', 'from',
    'is', 'are', 'was', 'were', 'be', 'it', 'its', 'this', 'that', 'as', 'into', 'over', 'under',
  };

  /// Lower-cases and replaces accented letters with their ASCII base.
  static String foldAscii(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_folds[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// The normalised words of [raw]; see the class comment for the rules.
  static List<String> words(String raw) {
    final folded = foldAscii(raw).replaceAll(RegExp(r"['’]s\b"), '');
    final parts = folded
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.length > 1 && leadingArticles.contains(parts.first)) parts.removeAt(0);
    return parts;
  }

  /// The normalised form of [raw]: its [words] joined by one space.
  static String normalise(String raw) => words(raw).join(' ');

  /// True when the words of [needle] appear in order and next to each other
  /// among the words of [haystack]. Used to stop a clue naming the answer.
  static bool containsPhrase(String haystack, String needle) {
    final target = words(needle);
    if (target.isEmpty) return false;
    final source = words(haystack);
    for (var i = 0; i + target.length <= source.length; i++) {
      var match = true;
      for (var j = 0; j < target.length; j++) {
        if (source[i + j] != target[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  /// The normalised words of [raw] that carry meaning, for checking that a
  /// source excerpt really covers a subject.
  static List<String> significantWords(String raw) =>
      words(raw).where((w) => !commonWords.contains(w)).toList();
}
