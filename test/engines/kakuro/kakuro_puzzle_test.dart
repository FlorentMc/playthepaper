import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Map<String, dynamic> withCells(List<Object?> cells, {int width = 3, int height = 3}) =>
      {'width': width, 'height': height, 'cells': cells};

  test('parses a valid payload and reveal', () {
    final puzzle = smallPuzzle();
    expect(puzzle.width, 3);
    expect(puzzle.height, 3);
    expect(puzzle.whiteCells, [4, 5, 7, 8]);
    expect(puzzle.runs.length, 4);
    expect(puzzle.solution, [0, 0, 0, 0, 1, 2, 0, 3, 1]);
    expect(puzzle.cells[1].isClue, isTrue);
    expect(puzzle.cells[1].down, 4);
    expect(puzzle.cells[1].across, isNull);
    expect(puzzle.cells[0].isBlock, isTrue);
    expect(puzzle.toPayload(), smallPayload());
    expect(puzzle.toReveal(), smallReveal());
  });

  test('every white cell lies in exactly one across and one down run', () {
    final grid = smallPuzzle().grid;
    for (final w in grid.whiteCells) {
      final through = grid.runsThrough(w);
      expect(through.length, 2);
      expect(through.where((r) => r.isAcross).length, 1);
      expect(grid.runs.where((r) => r.cells.contains(w)).length, 2);
    }
    expect(grid.runsThrough(0), isEmpty);
    expect(grid.runs[0].isAcross, isFalse);
    expect(grid.runs[0].cells, [4, 7]);
    expect(grid.runs[0].sum, 4);
    expect(grid.runs[0].clueCell, 1);
  });

  test('rejects missing or malformed fields', () {
    expect(() => KakuroPuzzle.parse({}, smallReveal()), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {}), throwsFormatException);
    expect(() => KakuroPuzzle.parse({'width': 3, 'height': 3}, smallReveal()), throwsFormatException);
    expect(() => KakuroPuzzle.parse({'width': '3', 'height': 3, 'cells': []}, smallReveal()), throwsFormatException);
    expect(() => KakuroPuzzle.parse({...smallPayload(), 'width': 1, 'height': 1}, smallReveal()), throwsFormatException);
    expect(() => KakuroPuzzle.parse({...smallPayload(), 'width': 13}, smallReveal()), throwsFormatException);
  });

  test('rejects the wrong number of cells and unknown cell tokens', () {
    final cells = smallPayload()['cells'] as List;
    expect(() => KakuroGrid.parsePayload(withCells(cells.sublist(1))), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells, '.'])), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[4] = 'x')), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[4] = 5)), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[1] = {'down': 'four', 'across': null})), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[1] = {'down': 0, 'across': null})), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[1] = {'down': 46, 'across': null})), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[0] = {'down': null, 'across': null})), throwsFormatException);
  });

  test('rejects a white cell with no clue in either direction', () {
    final cells = smallPayload()['cells'] as List;
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[3] = '#')), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[1] = '#')), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[1] = {'down': null, 'across': 3})), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells(List.filled(9, '#'))), throwsFormatException);
  });

  test('rejects a clue with no cells, a run of one cell and an impossible sum', () {
    final cells = smallPayload()['cells'] as List;
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[6] = {'down': 5, 'across': 4})), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[8] = '#')), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[3] = {'down': null, 'across': 2})), throwsFormatException);
    expect(() => KakuroGrid.parsePayload(withCells([...cells]..[3] = {'down': null, 'across': 18})), throwsFormatException);
    expect(KakuroGrid.parsePayload(withCells([...cells]..[3] = {'down': null, 'across': 17})).runs.length, 4);
  });

  test('rejects a reveal with the wrong shape', () {
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': '####12#31'}), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '#', '1', '2', '#', '3']}), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '1', '1', '2', '#', '3', '1']}), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '#', '#', '2', '#', '3', '1']}), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '#', '0', '2', '#', '3', '1']}), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '#', 1, '2', '#', '3', '1']}), throwsFormatException);
    expect(() => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '#', '12', '2', '#', '3', '1']}), throwsFormatException);
  });

  test('a repeated digit in a run is rejected', () {
    final grid = gridOf(repeatPayload());
    expect(grid.firstViolation([0, 0, 0, 0, 2, 2, 0, 2, 4]), contains('repeats the digit 2'));
    expect(() => KakuroPuzzle.parse(repeatPayload(), repeatReveal()), throwsFormatException);
    expect(
      () => KakuroPuzzle(grid: grid, solution: [0, 0, 0, 0, 2, 2, 0, 2, 4]),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('repeats'))),
    );
  });

  test('a wrong sum is rejected', () {
    final grid = smallPuzzle().grid;
    expect(grid.firstViolation([0, 0, 0, 0, 1, 2, 0, 3, 4]), contains('sums to 6, not 3'));
    expect(grid.firstViolation([0, 0, 0, 0, 1, 2, 0, 4, 1]), contains('sums to 5, not 4'));
    expect(
      () => KakuroPuzzle.parse(smallPayload(), {'solution': ['#', '#', '#', '#', '1', '2', '#', '3', '4']}),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('sums to'))),
    );
  });

  test('an empty white cell is a violation', () {
    final grid = smallPuzzle().grid;
    expect(grid.firstViolation([0, 0, 0, 0, 1, 2, 0, 3, 0]), contains('not a digit'));
    expect(grid.firstViolation([0, 0, 0]), contains('entries'));
    expect(grid.isSolvedBy([0, 0, 0, 0, 1, 2, 0, 3, 1]), isTrue);
  });

  test('a board with two solutions is rejected', () {
    expect(gridOf(twoSolutionPayload()).isSolvedBy([0, 0, 0, 0, 1, 2, 0, 2, 1]), isTrue);
    expect(
      () => KakuroPuzzle.parse(twoSolutionPayload(), twoSolutionReveal()),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('unique'))),
    );
  });

  test('the reveal solves the payload and matches the solver', () {
    final puzzle = smallPuzzle();
    expect(puzzle.grid.firstViolation(puzzle.solution), isNull);
    expect(KakuroSolver.solve(puzzle.grid), puzzle.solution);
    expect(KakuroSolver.countSolutions(puzzle.grid), 1);
  });

  test('conflicts lists cells that repeat a digit in a run', () {
    final grid = smallPuzzle().grid;
    expect(grid.conflicts([0, 0, 0, 0, 1, 0, 0, 1, 0]), {4, 7});
    expect(grid.conflicts([0, 0, 0, 0, 1, 1, 0, 0, 0]), {4, 5});
    expect(grid.conflicts([0, 0, 0, 0, 1, 2, 0, 3, 1]), isEmpty);
  });

  test('sum bounds follow the digits', () {
    expect(KakuroGrid.minSum(2), 3);
    expect(KakuroGrid.maxSum(2), 17);
    expect(KakuroGrid.minSum(5), 15);
    expect(KakuroGrid.maxSum(5), 35);
    expect(KakuroGrid.maxSum(9), 45);
    expect(KakuroGrid.bitCount(KakuroGrid.allDigits), 9);
    expect(KakuroGrid.digitsOf(KakuroGrid.bit(3) | KakuroGrid.bit(8)).toList(), [3, 8]);
  });
}
