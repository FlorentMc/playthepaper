import 'package:playthepaper/engines/nonogram/nonogram.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('line arithmetic', () {
    test('minLength counts the runs and the gaps between them', () {
      expect(NonogramLine.minLength(const []), 0);
      expect(NonogramLine.minLength(const [5]), 5);
      expect(NonogramLine.minLength(const [2, 1, 3]), 8);
    });

    test('runs reads a mask left to right', () {
      expect(NonogramLine.runs(0, 5), isEmpty);
      expect(NonogramLine.runs(0x1F, 5), [5]);
      expect(NonogramLine.runs(0x0B, 5), [2, 1]);
      expect(NonogramLine.runs(0x11, 5), [1, 1]);
    });

    test('a full-width run fixes every cell', () {
      final d = NonogramLine.deduce(length: 5, clues: const [5], knownFilled: 0, knownEmpty: 0);
      expect(d.placements, 1);
      expect(d.filled, 0x1F);
      expect(d.empty, 0);
    });

    test('an overlapping run fixes only its middle', () {
      final d = NonogramLine.deduce(length: 5, clues: const [3], knownFilled: 0, knownEmpty: 0);
      expect(d.placements, 3);
      expect(d.filled, 0x04);
      expect(d.empty, 0);
    });

    test('a short run in a long line fixes nothing on its own', () {
      final d = NonogramLine.deduce(length: 5, clues: const [1], knownFilled: 0, knownEmpty: 0);
      expect(d.placements, 5);
      expect(d.filled, 0);
      expect(d.empty, 0);
    });

    test('an empty clue empties the whole line', () {
      final d = NonogramLine.deduce(length: 5, clues: const [], knownFilled: 0, knownEmpty: 0);
      expect(d.placements, 1);
      expect(d.empty, 0x1F);
    });

    test('known cells narrow the placements', () {
      final d = NonogramLine.deduce(length: 5, clues: const [2], knownFilled: 0x01, knownEmpty: 0);
      expect(d.placements, 1);
      expect(d.filled, 0x03);
      expect(d.empty, 0x1C);
    });

    test('a clue that cannot be placed is a contradiction', () {
      expect(
        NonogramLine.deduce(length: 5, clues: const [4], knownFilled: 0x11, knownEmpty: 0).isContradiction,
        isTrue,
      );
      expect(
        NonogramLine.deduce(length: 5, clues: const [1], knownFilled: 0, knownEmpty: 0x1F).isContradiction,
        isTrue,
      );
      expect(
        NonogramLine.deduce(length: 5, clues: const [], knownFilled: 0x01, knownEmpty: 0).isContradiction,
        isTrue,
      );
    });
  });

  group('solver', () {
    test('finds the one picture the clues describe', () {
      final puzzle = crossPuzzle();
      final solved = NonogramSolver.solve(width: 5, height: 5, rows: puzzle.rows, cols: puzzle.cols);
      expect(solved, puzzle.rowMasks);
    });

    test('counts one solution for a unique picture', () {
      expect(NonogramSolver.countSolutions(arrowPuzzle()), 1);
    });

    test('counts two for clues that swap a pair of cells', () {
      // Two lone cells in each of two rows and four columns: the pairs swap.
      expect(
        NonogramSolver.countSolutionsOf(
          width: 5,
          height: 5,
          rows: const [
            [1, 1],
            [],
            [1, 1],
            [],
            [],
          ],
          cols: const [
            [1],
            [1],
            [],
            [1],
            [1],
          ],
        ),
        2,
      );
      expect(
        NonogramSolver.solve(
          width: 5,
          height: 5,
          rows: const [
            [1, 1],
            [],
            [1, 1],
            [],
            [],
          ],
          cols: const [
            [1],
            [1],
            [],
            [1],
            [1],
          ],
        ),
        isNull,
      );
    });

    test('counts none for clues that contradict each other', () {
      expect(
        NonogramSolver.countSolutionsOf(
          width: 5,
          height: 5,
          rows: const [
            [5],
            [],
            [],
            [],
            [],
          ],
          cols: const [
            [],
            [],
            [],
            [],
            [],
          ],
        ),
        0,
      );
    });

    test('counts none when the row and column totals disagree', () {
      expect(
        NonogramSolver.countSolutionsOf(
          width: 5,
          height: 5,
          rows: const [
            [3],
            [],
            [],
            [],
            [],
          ],
          cols: const [
            [1],
            [1],
            [],
            [],
            [],
          ],
        ),
        0,
      );
    });

    test('reports that a picture needs no guessing and how many sweeps it takes', () {
      final analysis = NonogramSolver.analyse(crossPuzzle());
      expect(analysis.isUnique, isTrue);
      expect(analysis.lineSolvable, isTrue);
      expect(analysis.sweeps, greaterThanOrEqualTo(1));
    });

    test('solves every authored picture back to its own drawing', () {
      for (final picture in nonogramPictures) {
        final puzzle = NonogramPuzzle.fromPicture(picture: picture.rows, title: picture.title);
        final solved = NonogramSolver.solve(width: puzzle.width, height: puzzle.height, rows: puzzle.rows, cols: puzzle.cols);
        expect(solved, puzzle.rowMasks, reason: '${picture.size}×${picture.size} "${picture.title}"');
      }
    });
  });
}
