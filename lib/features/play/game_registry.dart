import '../../core/game_kind.dart';
import '../games/binary/binary_screen.dart';
import '../games/bridges/bridges_screen.dart';
import '../games/chronology/chronology_screen.dart';
import '../games/compass/compass_screen.dart';
import '../games/crossmatch/crossmatch_screen.dart';
import '../games/crossword/crossword_screen.dart';
import '../games/fiveclues/fiveclues_screen.dart';
import '../games/groups/groups_screen.dart';
import '../games/kakuro/kakuro_screen.dart';
import '../games/letters/letters_screen.dart';
import '../games/linked/linked_screen.dart';
import '../games/loop/loop_screen.dart';
import '../games/merge/merge_screen.dart';
import '../games/nonogram/nonogram_screen.dart';
import '../games/quiz/quiz_screen.dart';
import '../games/regions/regions_screen.dart';
import '../games/sudoku/sudoku_screen.dart';
import '../games/tangram/tangram_screen.dart';
import '../games/target/target_screen.dart';
import '../games/uncover/uncover_screen.dart';
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
    GameKind.bridges: (context, play) => BridgesScreen(play: play),
    GameKind.binary: (context, play) => BinaryScreen(play: play),
    GameKind.nonogram: (context, play) => NonogramScreen(play: play),
    GameKind.kakuro: (context, play) => KakuroScreen(play: play),
    GameKind.regions: (context, play) => RegionsScreen(play: play),
    GameKind.loop: (context, play) => LoopScreen(play: play),
    GameKind.target: (context, play) => TargetScreen(play: play),
    GameKind.tangram: (context, play) => TangramScreen(play: play),
    GameKind.merge: (context, play) => MergeScreen(play: play),
    GameKind.uncover: (context, play) => UncoverScreen(play: play),
    GameKind.fiveclues: (context, play) => FiveCluesScreen(play: play),
    GameKind.groups: (context, play) => GroupsScreen(play: play),
    GameKind.linked: (context, play) => LinkedScreen(play: play),
    GameKind.chronology: (context, play) => ChronologyScreen(play: play),
    GameKind.crossmatch: (context, play) => CrossmatchScreen(play: play),
    GameKind.compass: (context, play) => CompassScreen(play: play),
  };

  static final Map<GameKind, GameHelp> help = {
    GameKind.word: WordScreen.help,
    GameKind.sudoku: SudokuScreen.help,
    GameKind.letters: LettersScreen.help,
    GameKind.crossword: CrosswordScreen.help,
    GameKind.quiz: QuizScreen.help,
    GameKind.bridges: BridgesScreen.help,
    GameKind.binary: BinaryScreen.help,
    GameKind.nonogram: NonogramScreen.help,
    GameKind.kakuro: KakuroScreen.help,
    GameKind.regions: RegionsScreen.help,
    GameKind.loop: LoopScreen.help,
    GameKind.target: TargetScreen.help,
    GameKind.tangram: TangramScreen.help,
    GameKind.merge: MergeScreen.help,
    GameKind.uncover: UncoverScreen.help,
    GameKind.fiveclues: FiveCluesScreen.help,
    GameKind.groups: GroupsScreen.help,
    GameKind.linked: LinkedScreen.help,
    GameKind.chronology: ChronologyScreen.help,
    GameKind.crossmatch: CrossmatchScreen.help,
    GameKind.compass: CompassScreen.help,
  };

  /// One-line description for the home page.
  static const Map<GameKind, String> blurbs = {
    GameKind.word: 'Six letters, six guesses, first letter given.',
    GameKind.sudoku: 'Three difficulties, notes and undo.',
    GameKind.letters: 'Seven letters. Find the words. Find the pangram.',
    GameKind.crossword: 'A compact 5×5 for a quick coffee.',
    GameKind.quiz: 'Five questions from today\'s stories. One wager.',
    GameKind.bridges: 'Join the islands with the right number of bridges.',
    GameKind.binary: 'Two symbols, equal counts, no three in a row.',
    GameKind.nonogram: 'Uncover the picture from the row and column clues.',
    GameKind.kakuro: 'Crossing sums with the digits 1 to 9.',
    GameKind.regions: 'Fill each region 1 to N; equal digits never touch.',
    GameKind.loop: 'One closed loop, guided by the numbers.',
    GameKind.target: 'Reach the target with six numbers.',
    GameKind.tangram: 'Seven pieces, one silhouette.',
    GameKind.merge: 'Slide and merge to 2048. A daily challenge and free play.',
    GameKind.uncover: 'Guess words to reveal the hidden story.',
    GameKind.fiveclues: 'Five clues, one shared answer.',
    GameKind.groups: 'Sort twelve tiles into three groups of four.',
    GameKind.linked: 'Three small answers point to one subject.',
    GameKind.chronology: 'Put four events in order.',
    GameKind.crossmatch: 'Nine tiles, a 3×3 grid, every row and column a criterion.',
    GameKind.compass: 'Guess the day\'s word by how close you are.',
  };
}
