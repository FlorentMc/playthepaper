import 'package:playthepaper/engines/loop/loop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final grid = LoopGrid(3, 3);
  final solution = linesOf(smallH, smallV);
  List<int> clues(String text) => LoopPuzzle.parseClues(text, grid.cellCount);
  List<int> blank(LoopGrid g) => List.filled(g.edgeCount, LoopSolver.unknown);

  test('finds the one solution of the fixture', () {
    expect(LoopSolver.countSolutions(grid, clues(smallClues)), 1);
    expect(LoopSolver.solve(grid, clues(smallClues)), solution);
    expect(LoopSolver.countSolutions(grid, clues(smallSparseClues)), 1);
    expect(LoopSolver.solve(grid, clues(smallSparseClues)), solution);
    expect(LoopSolver.countSolutions(grid, clues(smallHardClues)), 1);
    expect(LoopSolver.solve(grid, clues(smallHardClues)), solution);
  });

  test('a puzzle with two solutions is rejected by the uniqueness check', () {
    final two = LoopGrid(2, 2);
    expect(LoopSolver.countSolutions(two, clues2(two, '3...')), 2);
    expect(LoopSolver.countSolutions(two, clues2(two, '3...'), limit: 10), 4);
    expect(LoopSolver.countSolutions(grid, clues('.........')), 2);
    expect(LoopSolver.countSolutions(two, clues2(two, '....'), limit: 100), 13);
    expect(LoopSolver.countSolutions(grid, clues('.........'), limit: 1000), 213);
  });

  test('contradictory clues have no solution', () {
    final two = LoopGrid(2, 2);
    expect(LoopSolver.countSolutions(two, clues2(two, '0000')), 0);
    expect(LoopSolver.countSolutions(two, clues2(two, '3333')), 0);
    expect(LoopSolver.solve(two, clues2(two, '3333')), isNull);
    expect(LoopSolver.countSolutions(grid, clues('3.......3'), limit: 0), 0);
  });

  test('known edges narrow the count and a bad set has none', () {
    final known = blank(grid);
    known[grid.h(0, 0)] = 0;
    expect(LoopSolver.countSolutions(grid, clues('.........'), known: known, limit: 1000), inInclusiveRange(1, 212));
    final wrong = blank(grid)..[grid.h(0, 0)] = 0;
    expect(LoopSolver.countSolutions(grid, clues(smallClues), known: wrong), 0);
    final branch = blank(grid)
      ..[grid.h(1, 0)] = 1
      ..[grid.h(1, 1)] = 1
      ..[grid.v(0, 1)] = 1;
    expect(LoopSolver.countSolutions(grid, clues('.........'), known: branch), 0);
    expect(() => LoopSolver.countSolutions(grid, clues(smallClues), known: [1]), throwsArgumentError);
    expect(() => LoopSolver.countSolutions(grid, clues(smallClues), known: blank(grid)..[0] = 2), throwsArgumentError);
  });

  test('a loop closed early with clues still unmet is a contradiction', () {
    final known = blank(grid);
    for (final e in grid.cellEdges[grid.cell(0, 0)]) {
      known[e] = 1;
    }
    expect(LoopSolver.countSolutions(grid, clues('.........'), known: known), 1);
    expect(LoopSolver.countSolutions(grid, clues('........1'), known: known), 0);
    expect(LoopSolver.propagate(grid, clues('........1'), known), isNull);
    final closed = LoopSolver.propagate(grid, clues('.........'), known)!;
    expect(closed.contains(LoopSolver.unknown), isFalse);
    expect(closed.where((v) => v == 1).length, 4);
  });

  test('propagation applies the counting rules', () {
    final zero = LoopSolver.propagate(grid, clues('....0....'), blank(grid))!;
    for (final e in grid.cellEdges[grid.cell(1, 1)]) {
      expect(zero[e], 0);
    }
    expect(zero.where((v) => v == LoopSolver.unknown).length, grid.edgeCount - 4);

    final corner = blank(grid)..[grid.h(0, 0)] = 1;
    final dot = LoopSolver.propagate(grid, clues('.........'), corner)!;
    expect(dot[grid.v(0, 0)], 1, reason: 'a corner dot with one line must take the other');

    final trivial = LoopSolver.propagate(grid, clues(smallTrivialClues), blank(grid))!;
    expect(trivial.contains(LoopSolver.unknown), isFalse);
    expect(List.generate(grid.edgeCount, (e) => trivial[e] == 1), solution);

    expect(LoopSolver.propagate(grid, clues('.........'), blank(grid)..[grid.h(0, 0)] = 1..[grid.v(0, 0)] = 0), isNull);
  });

  test('one-step reasoning settles a 3 in a corner and solves the sparse fixture', () {
    final corner = LoopSolver.deduce(grid, clues('3........'), blank(grid))!;
    expect(corner.values[grid.h(0, 0)], 1);
    expect(corner.values[grid.v(0, 0)], 1);
    expect(corner.complete, isFalse);
    expect(corner.steps, greaterThan(0));

    final sparse = LoopSolver.deduce(grid, clues(smallSparseClues), blank(grid))!;
    expect(sparse.complete, isTrue);
    expect(List.generate(grid.edgeCount, (e) => sparse.values[e] == 1), solution);
    expect(sparse.steps, greaterThan(0));

    final hard = LoopSolver.deduce(grid, clues(smallHardClues), blank(grid))!;
    expect(hard.complete, isFalse);
    expect(LoopSolver.deduce(grid, clues('........1'), blank(grid)..[grid.h(0, 0)] = 1..[grid.v(0, 0)] = 0), isNull);
  });

  test('tiers grade by the reasoning needed', () {
    expect(LoopSolver.tier(grid, clues(smallTrivialClues)), LoopTier.trivial);
    expect(LoopSolver.tier(grid, clues(smallSparseClues)), LoopTier.fair);
    expect(LoopSolver.tier(grid, clues(smallHardClues)), LoopTier.hard);
    expect(LoopSolver.tier(grid, clues('.........')), LoopTier.hard);
    expect(LoopSolver.tier(LoopGrid(2, 2), clues2(LoopGrid(2, 2), '3333')), LoopTier.hard);
  });
}

List<int> clues2(LoopGrid grid, String text) => LoopPuzzle.parseClues(text, grid.cellCount);
