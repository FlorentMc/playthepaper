import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/engines/crossword/crossword_puzzle.dart';
import 'package:daypencil/engines/letters/letters.dart';
import 'package:daypencil/engines/quiz/quiz_engine.dart';
import 'package:daypencil/engines/sudoku/sudoku.dart';
import 'package:daypencil/engines/word/word_engine.dart';

/// Runs a puzzle through its engine's parser. Returns null when valid,
/// otherwise a one-line description of the problem.
///
/// Engine hooks are wired in as each engine lands; an unwired game is
/// reported so the validator never silently passes it.
String? checkPuzzleWithEngine(PuzzleRecord record) {
  final check = engineChecks[record.game];
  if (check == null) return 'no engine validator for ${record.game.slug}';
  try {
    check(record);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

typedef EngineCheck = void Function(PuzzleRecord record);

final Map<GameKind, EngineCheck> engineChecks = {
  GameKind.word: (r) => WordPuzzle.parse(r.payload, r.reveal),
  GameKind.sudoku: (r) => SudokuPuzzle.parse(r.payload, r.reveal),
  GameKind.letters: (r) => LettersPuzzle.parse(r.payload, r.reveal),
  GameKind.crossword: (r) => CrosswordPuzzle.parse(r.payload, r.reveal),
  GameKind.quiz: (r) => QuizPuzzle.parse(r.payload, r.reveal),
};

