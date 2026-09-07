import '../../core/game_kind.dart';
import '../games/crossword/crossword_screen.dart';
import '../games/letters/letters_screen.dart';
import '../games/quiz/quiz_screen.dart';
import '../games/sudoku/sudoku_screen.dart';
import '../games/word/word_screen.dart';
import 'play_context.dart';

/// Maps each game to its screen and help. Game modules own their entry files;
/// this registry is the only place that knows about all of them.
class GameRegistry {
  static final Map<GameKind, GameScreenBuilder> screens = {
    GameKind.word: (context, play) => WordScreen(play: play),
    GameKind.sudoku: (context, play) => SudokuScreen(play: play),
    GameKind.letters: (context, play) => LettersScreen(play: play),
    GameKind.crossword: (context, play) => CrosswordScreen(play: play),
    GameKind.quiz: (context, play) => QuizScreen(play: play),
  };

  static final Map<GameKind, GameHelp> help = {
    GameKind.word: WordScreen.help,
    GameKind.sudoku: SudokuScreen.help,
    GameKind.letters: LettersScreen.help,
    GameKind.crossword: CrosswordScreen.help,
    GameKind.quiz: QuizScreen.help,
  };

  /// One-line description for the home page cards.
  static const Map<GameKind, String> blurbs = {
    GameKind.word: 'Six letters, six guesses, first letter given.',
    GameKind.sudoku: 'Three difficulties, notes and undo.',
    GameKind.letters: 'Seven letters. Find the words. Find the pangram.',
    GameKind.crossword: 'A compact 5×5 for a quick coffee.',
    GameKind.quiz: 'Five questions from today\'s stories. One wager.',
  };
}
