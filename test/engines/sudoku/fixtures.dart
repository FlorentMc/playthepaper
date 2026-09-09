import 'package:playthepaper/engines/sudoku/sudoku.dart';

/// The Wikipedia example: solvable with singles alone.
const singlesOnlyGivens = '530070000600195000098000060800060003400803001700020006060000280000419005000080079';
const singlesOnlySolution = '534678912672195348198342567859761423426853791713924856961537284287419635345286179';

/// SudokuWiki technique examples.
const nakedPairGivens = '400000938032094100095300240370609004529001673604703090957008300003900400240030709';
const hiddenPairGivens = '000000000904607000076804100309701080008000300050308702007502610000403208000000000';

/// Needs an X-wing; beyond the grader's techniques.
const xWingGivens = '100000569492056108056109240009640801064010000218035604040500016905061402621000005';

List<int> cells(String text, {bool allowBlank = true}) =>
    SudokuGrid.parseCells(text, field: 'fixture', allowBlank: allowBlank);

/// A solved grid with rows 0 and 1 blanked. Swapping those two rows of the
/// original is another valid solution, so at least two exist.
List<int> twoSolutionGrid(List<int> solution) {
  final grid = List<int>.of(solution);
  for (var i = 0; i < 18; i++) {
    grid[i] = 0;
  }
  return grid;
}
