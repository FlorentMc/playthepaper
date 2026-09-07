import 'letters_puzzle.dart';
import 'letters_rank.dart';

/// What happened to a submitted word.
sealed class SubmitOutcome {
  const SubmitOutcome();
}

class SubmitTooShort extends SubmitOutcome {
  const SubmitTooShort();
}

class SubmitMissingCenter extends SubmitOutcome {
  const SubmitMissingCenter();
}

class SubmitBadLetters extends SubmitOutcome {
  const SubmitBadLetters();
}

class SubmitNotInList extends SubmitOutcome {
  const SubmitNotInList();
}

class SubmitAlreadyFound extends SubmitOutcome {
  const SubmitAlreadyFound();
}

class SubmitAccepted extends SubmitOutcome {
  const SubmitAccepted({required this.word, required this.points, required this.isPangram, required this.state});

  final String word;
  final int points;
  final bool isPangram;

  /// The state with [word] added.
  final LettersState state;
}

/// The words found so far, in the order they were found.
class LettersState {
  LettersState({required this.puzzle, List<String> found = const [], this.isFinished = false})
    : found = List.unmodifiable(found);

  final LettersPuzzle puzzle;
  final List<String> found;

  /// Set by [finish]; no more words are accepted after that.
  final bool isFinished;

  int get points => found.fold(0, (sum, word) => sum + puzzle.score(word));

  LettersRank get rank => LettersRank.rankFor(points, puzzle.maxScore);

  int get pangramsFound => found.where(puzzle.isPangramWord).length;

  List<String> get foundSorted => found.toList()..sort();

  bool get isComplete => found.length == puzzle.answers.length;

  SubmitOutcome submit(String raw) {
    if (isFinished) throw StateError('The puzzle is finished');
    final word = raw.trim().toUpperCase();
    if (word.length < puzzle.minLength) return const SubmitTooShort();
    if (!word.contains(puzzle.center)) return const SubmitMissingCenter();
    for (final ch in word.split('')) {
      if (!puzzle.letters.contains(ch)) return const SubmitBadLetters();
    }
    if (found.contains(word)) return const SubmitAlreadyFound();
    if (!puzzle.contains(word)) return const SubmitNotInList();
    return SubmitAccepted(
      word: word,
      points: puzzle.score(word),
      isPangram: puzzle.isPangramWord(word),
      state: LettersState(puzzle: puzzle, found: [...found, word]),
    );
  }

  LettersState finish() => LettersState(puzzle: puzzle, found: found, isFinished: true);

  Map<String, dynamic> toJson() => {'found': found, 'finished': isFinished};

  /// Restores saved progress. Words that are not answers, or repeat, are dropped
  /// so stale progress never breaks play.
  static LettersState fromJson(LettersPuzzle puzzle, Map<String, dynamic> json) {
    final raw = json['found'];
    final found = <String>[];
    if (raw is List) {
      for (final w in raw) {
        if (w is String && puzzle.contains(w) && !found.contains(w)) found.add(w);
      }
    }
    return LettersState(puzzle: puzzle, found: found, isFinished: json['finished'] == true);
  }
}
