import 'package:playthepaper/engines/binary/binary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('a valid solution counts as one and solve returns it', () {
    final solution = cells(solution6, 6);
    expect(BinarySolver.countSolutions(solution, 6), 1);
    expect(BinarySolver.countSolutions(cells(givens6, 6), 6), 1);
    expect(BinarySolver.solve(cells(givens6, 6), 6), solution);
  });

  test('a grid that breaks a rule has no solutions', () {
    expect(BinarySolver.countSolutions(cells(tripleOnly6, 6), 6), 0);
    expect(BinarySolver.countSolutions(cells(duplicateRows6, 6), 6), 0);
    expect(BinarySolver.countSolutions(cells(unequalCounts6, 6), 6), 0);
    expect(BinarySolver.solve(cells('11.1............', 4), 4), isNull);
    expect(BinarySolver.propagate(cells('111.............', 4), 4), isNull);
    expect(BinarySolver.countSolutions(cells('0011001.........', 4), 4), 0, reason: 'a row cannot repeat a finished one');
  });

  test('a checkerboard of blanks leaves exactly two solutions', () {
    final grid = twoSolutionGrid();
    expect(BinarySolver.countSolutions(grid, 6), 2);
    expect(BinarySolver.countSolutions(grid, 6, limit: 1), 1);
    expect(BinarySolver.countSolutions(grid, 6, limit: 5), 2);
  });

  test('an empty grid has many solutions', () {
    expect(BinarySolver.countSolutions(List.filled(16, BinaryRules.empty), 4, limit: 10), 10);
    expect(BinarySolver.countSolutions(List.filled(64, BinaryRules.empty), 8), 2);
  });

  test('propagation fills pairs and gaps', () {
    final out = BinarySolver.propagate(cells('11...........1.1', 4), 4, basicOnly: true)!;
    expect(out[2], 0, reason: 'a pair forces the next cell');
    expect(out[14], 0, reason: 'a gap takes the other symbol');
    expect(out[3], BinaryRules.empty, reason: 'the basic rule cannot count');
  });

  test('propagation completes a line with half its symbols', () {
    final out = BinarySolver.propagate(cells('1.1.............', 4), 4)!;
    expect(out.sublist(0, 4), [1, 0, 1, 0]);
  });

  test('propagation keeps a nearly finished line from copying a finished one', () {
    final grid = cells('0011010.1.01${'.' * 24}', 6);
    final out = BinarySolver.propagate(grid, 6)!;
    expect(out.sublist(6, 12), [0, 1, 1, 0, 0, 1]);
    final basic = BinarySolver.propagate(grid, 6, basicOnly: true)!;
    expect(basic[7], BinaryRules.empty);
    expect(basic[9], BinaryRules.empty);
  });

  test('a puzzle generated for propagation is solved by propagation', () {
    expect(BinarySolver.solvesByPropagation(cells(givens6, 6), 6), isTrue);
    expect(BinarySolver.solvesByPropagation(cells(givens6, 6), 6, basicOnly: true), isFalse);
    expect(BinarySolver.solvesByPropagation(twoSolutionGrid(), 6), isFalse);
  });
}
