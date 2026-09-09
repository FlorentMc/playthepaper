import 'package:playthepaper/engines/binary/binary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Map<String, dynamic> payload({int size = 6, String givens = givens6}) => {'size': size, 'givens': givens};
  Map<String, dynamic> reveal([String solution = solution6]) => {'solution': solution};

  test('parses a valid payload and reveal', () {
    final puzzle = BinaryPuzzle.parse(payload(), reveal());
    expect(puzzle.size, 6);
    expect(puzzle.cellCount, 36);
    expect(puzzle.givens, cells(givens6, 6));
    expect(puzzle.solution, cells(solution6, 6, allowBlank: false));
    expect(puzzle.givenCount, 19);
    expect(puzzle.isGiven(0), isTrue);
    expect(puzzle.isGiven(1), isFalse);
    expect(puzzle.toPayload(), payload());
    expect(puzzle.toReveal(), reveal());
  });

  test('rejects missing or mistyped fields', () {
    expect(() => BinaryPuzzle.parse({}, reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse({'givens': givens6}, reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse({'size': '6', 'givens': givens6}, reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse({'size': 6, 'givens': 1}, reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(), {}), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(), {'solution': 1}), throwsFormatException);
  });

  test('rejects an odd or out-of-range size', () {
    expect(() => BinaryPuzzle.parse(payload(size: 5), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(size: 2), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(size: 18), reveal()), throwsFormatException);
  });

  test('rejects wrong lengths and characters', () {
    expect(() => BinaryPuzzle.parse(payload(givens: givens6.substring(1)), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(givens: '${givens6}0'), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(givens: 'x${givens6.substring(1)}'), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(givens: '2${givens6.substring(1)}'), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(), reveal('.${solution6.substring(1)}')), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(), reveal(solution6.substring(1))), throwsFormatException);
  });

  test('rejects givens that disagree with the solution', () {
    final changed = '1${givens6.substring(1)}';
    expect(() => BinaryPuzzle.parse(payload(givens: changed), reveal()), throwsFormatException);
  });

  test('rejects a solution with unequal counts in a line', () {
    expect(BinaryRules.overCountCells(cells(unequalCounts6, 6), 6), isNotEmpty);
    expect(() => BinaryPuzzle.parse(payload(givens: '.' * 36), reveal(unequalCounts6)), throwsFormatException);
  });

  test('rejects a solution with three equal symbols in a row', () {
    final grid = cells(tripleOnly6, 6);
    expect(BinaryRules.overCountCells(grid, 6), isEmpty);
    expect(BinaryRules.duplicateLineCells(grid, 6), isEmpty);
    expect(BinaryRules.tripleCells(grid, 6), isNotEmpty);
    expect(() => BinaryPuzzle.parse(payload(givens: '.' * 36), reveal(tripleOnly6)), throwsFormatException);
  });

  test('rejects a solution with two equal rows', () {
    final grid = cells(duplicateRows6, 6);
    expect(BinaryRules.overCountCells(grid, 6), isEmpty);
    expect(BinaryRules.tripleCells(grid, 6), isEmpty);
    expect(BinaryRules.duplicateLineCells(grid, 6), {12, 13, 14, 15, 16, 17, 30, 31, 32, 33, 34, 35});
    expect(() => BinaryPuzzle.parse(payload(givens: '.' * 36), reveal(duplicateRows6)), throwsFormatException);
  });

  test('rejects a solution with two equal columns', () {
    final text = transpose(duplicateRows6, 6);
    final grid = cells(text, 6);
    expect(BinaryRules.overCountCells(grid, 6), isEmpty);
    expect(BinaryRules.tripleCells(grid, 6), isEmpty);
    expect(BinaryRules.duplicateLineCells(grid, 6), isNotEmpty);
    expect(() => BinaryPuzzle.parse(payload(givens: '.' * 36), reveal(text)), throwsFormatException);
  });

  test('rejects givens with more than one solution', () {
    final ambiguous = BinaryRules.formatCells(twoSolutionGrid());
    expect(() => BinaryPuzzle.parse(payload(givens: ambiguous), reveal()), throwsFormatException);
    expect(() => BinaryPuzzle.parse(payload(givens: '.' * 36), reveal()), throwsFormatException);
  });

  test('accepts a fully given grid and a 4×4', () {
    expect(BinaryPuzzle.parse(payload(givens: solution6), reveal()).givenCount, 36);
    final p = BinaryPuzzle.parse({'size': 4, 'givens': '0.1.1..1.1..1.1.'}, {'solution': solution4});
    expect(p.size, 4);
  });

  test('the constructor validates raw lists', () {
    expect(() => BinaryPuzzle(size: 6, givens: List.filled(35, -1), solution: cells(solution6, 6)), throwsFormatException);
    final bad = cells(givens6, 6)..[1] = 2;
    expect(() => BinaryPuzzle(size: 6, givens: bad, solution: cells(solution6, 6)), throwsFormatException);
    expect(() => BinaryPuzzle(size: 7, givens: List.filled(49, -1), solution: List.filled(49, 0)), throwsFormatException);
  });
}
