import 'package:daypencil/engines/sudoku/sudoku.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Map<String, dynamic> payload([String givens = singlesOnlyGivens]) => {'givens': givens};
  Map<String, dynamic> reveal([String solution = singlesOnlySolution]) => {'solution': solution};

  test('parses a valid payload and reveal', () {
    final puzzle = SudokuPuzzle.parse(payload(), reveal());
    expect(puzzle.givens, cells(singlesOnlyGivens));
    expect(puzzle.solution, cells(singlesOnlySolution, allowBlank: false));
    expect(puzzle.givenCount, 30);
    expect(puzzle.isGiven(0), isTrue);
    expect(puzzle.isGiven(2), isFalse);
    expect(puzzle.toPayload(), payload());
    expect(puzzle.toReveal(), reveal());
  });

  test('rejects missing fields', () {
    expect(() => SudokuPuzzle.parse({}, reveal()), throwsFormatException);
    expect(() => SudokuPuzzle.parse(payload(), {}), throwsFormatException);
    expect(() => SudokuPuzzle.parse({'givens': 1}, reveal()), throwsFormatException);
  });

  test('rejects wrong lengths and characters', () {
    expect(() => SudokuPuzzle.parse(payload(singlesOnlyGivens.substring(1)), reveal()), throwsFormatException);
    expect(() => SudokuPuzzle.parse(payload('${singlesOnlyGivens}0'), reveal()), throwsFormatException);
    expect(() => SudokuPuzzle.parse(payload('x${singlesOnlyGivens.substring(1)}'), reveal()), throwsFormatException);
    expect(() => SudokuPuzzle.parse(payload(), reveal('0${singlesOnlySolution.substring(1)}')), throwsFormatException);
  });

  test('rejects givens that disagree with the solution', () {
    final changed = '${singlesOnlyGivens.substring(0, 1)}9${singlesOnlyGivens.substring(2)}';
    expect(() => SudokuPuzzle.parse(payload(changed), reveal()), throwsFormatException);
  });

  test('rejects an invalid solution grid', () {
    final swapped = '${singlesOnlySolution.substring(0, 1)}5${singlesOnlySolution.substring(2)}';
    expect(() => SudokuPuzzle.parse(payload('0' * 81), reveal(swapped)), throwsFormatException);
  });

  test('rejects givens with more than one solution', () {
    final ambiguous = twoSolutionGrid(cells(singlesOnlySolution, allowBlank: false)).join();
    expect(() => SudokuPuzzle.parse(payload(ambiguous), reveal()), throwsFormatException);
    expect(() => SudokuPuzzle.parse(payload('0' * 81), reveal()), throwsFormatException);
  });

  test('the constructor validates raw lists', () {
    expect(() => SudokuPuzzle(givens: List.filled(80, 0), solution: cells(singlesOnlySolution)), throwsFormatException);
    final bad = cells(singlesOnlyGivens)..[0] = 10;
    expect(() => SudokuPuzzle(givens: bad, solution: cells(singlesOnlySolution)), throwsFormatException);
  });
}
