/// Feedback for one letter of a guess.
enum LetterFeedback { correct, misplaced, absent }

/// Scores [guess] against [answer], both uppercase and of equal length.
///
/// Exact matches are marked first. Misplaced marks are then allocated left
/// to right from the letters of the answer that were not exactly matched, so
/// a letter is never marked more times than it occurs in the answer.
List<LetterFeedback> evaluateGuess(String guess, String answer) {
  if (guess.length != answer.length) {
    throw ArgumentError('Guess "$guess" and answer "$answer" differ in length');
  }
  final n = answer.length;
  final result = List<LetterFeedback>.filled(n, LetterFeedback.absent);
  final remaining = <String, int>{};
  for (var i = 0; i < n; i++) {
    if (guess[i] == answer[i]) {
      result[i] = LetterFeedback.correct;
    } else {
      remaining[answer[i]] = (remaining[answer[i]] ?? 0) + 1;
    }
  }
  for (var i = 0; i < n; i++) {
    if (result[i] == LetterFeedback.correct) continue;
    final left = remaining[guess[i]] ?? 0;
    if (left > 0) {
      result[i] = LetterFeedback.misplaced;
      remaining[guess[i]] = left - 1;
    }
  }
  return result;
}
