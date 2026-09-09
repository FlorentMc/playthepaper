import 'package:playthepaper/engines/loop/loop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('parses a valid payload and reveal', () {
    final puzzle = smallPuzzle();
    expect(puzzle.width, 3);
    expect(puzzle.height, 3);
    expect(puzzle.clues, [3, 2, 2, 2, 2, 3, 0, 1, 1]);
    expect(puzzle.clueCount, 9);
    expect(puzzle.lineCount, 10);
    expect(puzzle.solution, linesOf(smallH, smallV));
    expect(puzzle.toPayload(), smallPayload());
    expect(puzzle.toReveal(), smallReveal());
    expect(puzzle.hasClue(0), isTrue);
    expect(puzzle.clueAt(6), 0);
  });

  test('accepts flat bit strings and blank clues', () {
    final puzzle = LoopPuzzle.parse(
      smallPayload(clues: smallSparseClues),
      smallReveal(h: smallH.join(), v: smallV.join()),
    );
    expect(puzzle.clueCount, 3);
    expect(puzzle.hasClue(1), isFalse);
    expect(puzzle.clueAt(1), -1);
    expect(puzzle.solution, linesOf(smallH, smallV));
    expect(puzzle.cluesString, smallSparseClues);
  });

  test('a valid solved board is accepted by the rules', () {
    final puzzle = smallPuzzle();
    expect(LoopRules.violation(puzzle.grid, puzzle.clues, puzzle.solution), isNull);
    expect(LoopRules.isSolved(puzzle.grid, puzzle.clues, puzzle.solution), isTrue);
  });

  test('rejects missing or mistyped fields', () {
    expect(() => LoopPuzzle.parse({}, smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse({'width': '3', 'height': 3, 'clues': smallClues}, smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse({'width': 3, 'height': 3}, smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), {}), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), {'edges': 'x'}), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), {'edges': {'h': smallH}}), throwsFormatException);
  });

  test('rejects sizes outside 2 to 12', () {
    expect(() => LoopPuzzle.parse(smallPayload(width: 1, clues: '333'), smallReveal()), throwsFormatException);
    expect(() => LoopGrid(13, 6), throwsFormatException);
    expect(() => LoopGrid(6, 0), throwsFormatException);
    expect(LoopGrid(2, 2).edgeCount, 12);
    expect(LoopGrid(12, 12).edgeCount, 312);
  });

  test('rejects clues of the wrong length or with bad characters', () {
    expect(() => LoopPuzzle.parse(smallPayload(clues: '32222301'), smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(clues: '3222230111'), smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(clues: '422223011'), smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(clues: '3 2223011'), smallReveal()), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(clues: '-22223011'), smallReveal()), throwsFormatException);
  });

  test('rejects reveal edges of the wrong shape or with bad characters', () {
    expect(() => LoopPuzzle.parse(smallPayload(), smallReveal(h: ['110', '101', '011'])), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), smallReveal(h: ['1100', '101', '011', '000'])), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), smallReveal(v: ['1010', '0101', '000'])), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), smallReveal(h: ['1x0', '101', '011', '000'])), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), smallReveal(h: '11010101100')), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(), smallReveal(h: 7)), throwsFormatException);
  });

  test('rejects a reveal that does not meet a clue', () {
    expect(() => LoopPuzzle.parse(smallPayload(clues: '222223011'), smallReveal()), throwsFormatException);
    final puzzle = smallPuzzle();
    final clues = List<int>.of(puzzle.clues)..[0] = 2;
    expect(LoopRules.violation(puzzle.grid, clues, puzzle.solution), contains('clue says 2'));
  });

  test('rejects an open path', () {
    final open = ['110', '101', '011', '000'];
    final v = ['1010', '0100', '0000'];
    expect(() => LoopPuzzle.parse(smallPayload(clues: '.........'), smallReveal(v: v)), throwsFormatException);
    final grid = LoopGrid(3, 3);
    expect(LoopRules.violation(grid, List.filled(9, -1), linesOf(open, v)), contains('open'));
  });

  test('rejects a branching dot', () {
    final h = ['110', '111', '011', '000'];
    expect(() => LoopPuzzle.parse(smallPayload(clues: '.........'), smallReveal(h: h)), throwsFormatException);
    final grid = LoopGrid(3, 3);
    expect(LoopRules.violation(grid, List.filled(9, -1), linesOf(h, smallV)), contains('three or more'));
  });

  test('rejects two separate loops even when every clue is met', () {
    final grid = LoopGrid(3, 3);
    final clues = LoopPuzzle.parseClues(twoLoopsClues, 9);
    final lines = linesOf(twoLoopsH, twoLoopsV);
    for (var cell = 0; cell < 9; cell++) {
      if (clues[cell] >= 0) expect(LoopRules.lineCount(grid.cellEdges[cell], lines), clues[cell], reason: 'cell $cell');
    }
    expect(LoopRules.violation(grid, clues, lines), 'more than one loop');
    expect(() => LoopPuzzle.parse(smallPayload(clues: twoLoopsClues), smallReveal(h: twoLoopsH, v: twoLoopsV)), throwsFormatException);
  });

  test('rejects an empty board', () {
    final grid = LoopGrid(3, 3);
    expect(LoopRules.violation(grid, List.filled(9, -1), List.filled(grid.edgeCount, false)), 'no lines drawn');
  });

  test('rejects clues with more than one solution', () {
    final h = ['10', '10', '00'];
    final v = ['110', '000'];
    expect(() => LoopPuzzle.parse(smallPayload(width: 2, height: 2, clues: '3...'), smallReveal(h: h, v: v)), throwsFormatException);
    expect(() => LoopPuzzle.parse(smallPayload(clues: '.........'), smallReveal()), throwsFormatException);
  });

  test('the constructor validates raw lists', () {
    final puzzle = smallPuzzle();
    expect(() => LoopPuzzle(width: 3, height: 3, clues: List.filled(8, -1), solution: puzzle.solution), throwsFormatException);
    expect(() => LoopPuzzle(width: 3, height: 3, clues: List.filled(9, 4), solution: puzzle.solution), throwsFormatException);
    expect(() => LoopPuzzle(width: 3, height: 3, clues: puzzle.clues, solution: List.filled(23, false)), throwsFormatException);
  });

  test('the grid wires cells, dots and edges together', () {
    final grid = LoopGrid(3, 2);
    expect(grid.hCount, 9);
    expect(grid.vCount, 8);
    expect(grid.edgeCount, 17);
    expect(grid.dotCount, 12);
    expect(grid.cellEdges[grid.cell(1, 2)], [grid.h(1, 2), grid.h(2, 2), grid.v(1, 2), grid.v(1, 3)]);
    expect(grid.dotEdges[grid.dot(0, 0)], [grid.h(0, 0), grid.v(0, 0)]);
    expect(grid.dotEdges[grid.dot(1, 1)], [grid.h(1, 0), grid.h(1, 1), grid.v(0, 1), grid.v(1, 1)]);
    expect(grid.edgeDots[grid.h(2, 1)], [grid.dot(2, 1), grid.dot(2, 2)]);
    expect(grid.edgeDots[grid.v(1, 3)], [grid.dot(1, 3), grid.dot(2, 3)]);
    expect(grid.edgeCells[grid.h(0, 1)], [grid.cell(0, 1)]);
    expect(grid.edgeCells[grid.h(1, 1)], [grid.cell(0, 1), grid.cell(1, 1)]);
    expect(grid.edgeCells[grid.v(0, 3)], [grid.cell(0, 2)]);
    expect(grid.isHorizontal(grid.h(2, 2)), isTrue);
    expect(grid.isHorizontal(grid.v(0, 0)), isFalse);
    expect(grid.edgeRow(grid.v(1, 3)), 1);
    expect(grid.edgeCol(grid.v(1, 3)), 3);
    expect(grid.edgeRow(grid.h(2, 1)), 2);
    expect(grid.edgeCol(grid.h(2, 1)), 1);
  });
}
