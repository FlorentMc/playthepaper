import 'word_puzzle.dart';

/// Why a guess was refused, or [ok].
enum GuessValidation {
  tooShort('Not enough letters'),
  wrongFirstLetter('The word starts with the given letter'),
  notInList('Not in the word list'),
  ok(null);

  const GuessValidation(this.message);

  /// User-facing reason, null for [ok].
  final String? message;
}

/// Checks a guess before it is submitted. [dictionary] holds valid words in
/// uppercase; [guess] is compared case-insensitively.
GuessValidation validateGuess(String guess, {required WordPuzzle puzzle, required Set<String> dictionary}) {
  final word = guess.toUpperCase();
  if (word.length < puzzle.length) return GuessValidation.tooShort;
  if (!word.startsWith(puzzle.firstLetter)) return GuessValidation.wrongFirstLetter;
  if (word.length != puzzle.length || !dictionary.contains(word)) return GuessValidation.notInList;
  return GuessValidation.ok;
}
