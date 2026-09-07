import 'package:equatable/equatable.dart';

/// The Daily Word puzzle: a hidden answer, its given first letter and the
/// number of guesses allowed. Parsed from the record's payload and reveal.
class WordPuzzle extends Equatable {
  const WordPuzzle({required this.length, required this.firstLetter, required this.maxGuesses, required this.answer});

  final int length;
  final String firstLetter;
  final int maxGuesses;
  final String answer;

  static final RegExp _upper = RegExp(r'^[A-Z]+$');

  static WordPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final length = payload['length'];
    if (length is! int || length < 1) throw const FormatException('Word payload needs a positive "length"');
    final maxGuesses = payload['maxGuesses'];
    if (maxGuesses is! int || maxGuesses < 1) {
      throw const FormatException('Word payload needs a positive "maxGuesses"');
    }
    final firstLetter = payload['firstLetter'];
    if (firstLetter is! String || firstLetter.length != 1 || !_upper.hasMatch(firstLetter)) {
      throw const FormatException('Word payload needs a single uppercase "firstLetter"');
    }
    final answer = reveal['answer'];
    if (answer is! String || !_upper.hasMatch(answer)) {
      throw const FormatException('Word reveal needs an uppercase A-Z "answer"');
    }
    if (answer.length != length) {
      throw FormatException('Word answer "$answer" is not $length letters');
    }
    if (!answer.startsWith(firstLetter)) {
      throw FormatException('Word answer "$answer" does not start with $firstLetter');
    }
    return WordPuzzle(length: length, firstLetter: firstLetter, maxGuesses: maxGuesses, answer: answer);
  }

  Map<String, dynamic> toPayload() => {'length': length, 'firstLetter': firstLetter, 'maxGuesses': maxGuesses};

  Map<String, dynamic> toReveal() => {'answer': answer};

  @override
  List<Object?> get props => [length, firstLetter, maxGuesses, answer];
}
