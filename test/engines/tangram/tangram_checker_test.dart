import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';

import 'fixtures.dart';

void main() {
  final puzzle = squarePuzzle();

  TangramCheck check(List<TangramPlacement> placements) =>
      TangramChecker.check(puzzle.mask, placements);

  test('the published arrangement makes the figure', () {
    final result = check(squareSolution);
    expect(result.isComplete, isTrue);
    expect(result.missed, 0);
    expect(result.spilled, 0);
    expect(result.overlap, 0);
  });

  test('the same figure built as a mirror image counts', () {
    expect(mirroredSquareSolution, isNot(squareSolution));
    expect(check(mirroredSquareSolution).isComplete, isTrue);
  });

  test('another arrangement of the same figure counts', () {
    expect(check(otherSquareSolution).isComplete, isTrue);
  });

  test('a piece left in the tray does not', () {
    final short = squareSolution.where((p) => p.piece != TangramPiece.square).toList();
    final result = check(short);
    expect(result.placed, 6);
    expect(result.isComplete, isFalse);
    expect(result.missed, greaterThan(0));
  });

  test('a piece on top of another does not', () {
    final overlapping = [
      for (final placement in squareSolution)
        placement.piece == TangramPiece.square ? placement.movedTo(2, 3) : placement,
    ];
    final result = check(overlapping);
    expect(result.placed, 7);
    expect(result.overlap, greaterThan(TangramChecker.maxOverlap));
    expect(result.isComplete, isFalse);
  });

  test('a piece one unit out of place does not', () {
    final nudged = [
      for (final placement in squareSolution)
        placement.piece == TangramPiece.smallTriangleA ? placement.movedTo(4, 2) : placement,
    ];
    final result = check(nudged);
    expect(result.isComplete, isFalse);
    expect(result.difference, greaterThan(TangramChecker.maxDifference));
  });

  test('a piece turned an eighth out of place does not', () {
    final turned = [
      for (final placement in squareSolution)
        placement.piece == TangramPiece.largeTriangleA ? placement.turned(1) : placement,
    ];
    expect(check(turned).isComplete, isFalse);
  });

  test('an empty board is as far off as it gets', () {
    final result = check(const []);
    expect(result.placed, 0);
    expect(result.difference, 1);
    expect(result.isComplete, isFalse);
  });
}
