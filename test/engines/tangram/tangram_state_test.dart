import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';

import 'fixtures.dart';

void main() {
  final puzzle = squarePuzzle();

  TangramState solvedExcept(TangramPiece missing) {
    var state = TangramState.initial(puzzle);
    for (final placement in squareSolution) {
      if (placement.piece == missing) continue;
      state = state.place(placement.piece, placement.x, placement.y,
          rotation: placement.rotation, flipped: placement.flipped);
    }
    return state;
  }

  test('a new board has every piece in the tray', () {
    final state = TangramState.initial(puzzle);
    expect(state.placed, isEmpty);
    expect(state.tray, TangramPiece.values);
    expect(state.isSolved, isFalse);
    expect(state.canUndo, isFalse);
    expect(state.hints, 0);
  });

  test('placing every piece where it belongs finishes the figure', () {
    var state = TangramState.initial(puzzle);
    for (final placement in squareSolution) {
      expect(state.isSolved, isFalse);
      state = state.place(placement.piece, placement.x, placement.y,
          rotation: placement.rotation, flipped: placement.flipped);
    }
    expect(state.placed, hasLength(7));
    expect(state.tray, isEmpty);
    expect(state.isSolved, isTrue);
  });

  test('a piece can be nudged, turned and sent back to the tray', () {
    var state = TangramState.initial(puzzle).place(TangramPiece.square, 4, 4);
    state = state.nudge(1, -1);
    expect(state.placementOf(TangramPiece.square), const TangramPlacement(piece: TangramPiece.square, x: 5, y: 3));
    state = state.turn(1);
    expect(state.placementOf(TangramPiece.square)!.rotation, 1);
    state = state.takeBack();
    expect(state.isPlaced(TangramPiece.square), isFalse);
    expect(state.selected, TangramPiece.square);
  });

  test('nothing moves while no piece is picked up', () {
    final state = TangramState.initial(puzzle);
    expect(state.nudge(1, 0), same(state));
    expect(state.turn(1), same(state));
    expect(state.flip(), same(state));
    expect(state.takeBack(), same(state));
    expect(state.reset(), same(state));
    expect(state.undo(), same(state));
  });

  test('only the parallelogram can be turned over', () {
    final square = TangramState.initial(puzzle).place(TangramPiece.square, 4, 4);
    expect(square.flip(), same(square));
    final parallelogram = TangramState.initial(puzzle).place(TangramPiece.parallelogram, 4, 4);
    expect(parallelogram.flip().placementOf(TangramPiece.parallelogram)!.flipped, isTrue);
  });

  test('a piece cannot be pushed off the board', () {
    final state = TangramState.initial(puzzle).place(TangramPiece.largeTriangleA, 0, 0);
    final placement = state.placementOf(TangramPiece.largeTriangleA)!;
    expect(placement.isOnBoard, isTrue);
    expect(placement.x, 2);
    expect(placement.y, 1);
    var pushed = state.place(TangramPiece.largeTriangleA, 8, 8);
    expect(pushed.placementOf(TangramPiece.largeTriangleA)!.isOnBoard, isTrue);
    pushed = pushed.nudge(3, 3);
    expect(pushed.placementOf(TangramPiece.largeTriangleA)!.isOnBoard, isTrue);
  });

  test('undo steps back through placing, moving and clearing', () {
    var state = TangramState.initial(puzzle).place(TangramPiece.square, 3, 3);
    state = state.nudge(1, 0);
    expect(state.placementOf(TangramPiece.square)!.x, 4);
    state = state.undo();
    expect(state.placementOf(TangramPiece.square)!.x, 3);
    state = state.undo();
    expect(state.isPlaced(TangramPiece.square), isFalse);
    expect(state.canUndo, isFalse);
  });

  test('reset clears the board in one step and undo brings it all back', () {
    var state = solvedExcept(TangramPiece.square);
    expect(state.placed, hasLength(6));
    state = state.reset();
    expect(state.placed, isEmpty);
    state = state.undo();
    expect(state.placed, hasLength(6));
  });

  test('a hint drops the next piece into place and is counted', () {
    var state = TangramState.initial(puzzle);
    state = state.hint();
    expect(state.hints, 1);
    expect(state.placementOf(TangramPiece.largeTriangleA), squareSolution.first);
    expect(state.undo().placed, isEmpty);
  });

  test('a hint sends back anything sitting where it needs to be', () {
    final answer = puzzle.solutionFor(TangramPiece.largeTriangleA);
    var state = TangramState.initial(puzzle).place(TangramPiece.square, answer.x, answer.y);
    state = state.hint();
    expect(state.isPlaced(TangramPiece.largeTriangleA), isTrue);
    expect(state.isPlaced(TangramPiece.square), isFalse);
  });

  test('hinting seven times finishes the figure', () {
    var state = TangramState.initial(puzzle);
    for (var i = 0; i < 7; i++) {
      state = state.hint();
    }
    expect(state.hints, 7);
    expect(state.isSolved, isTrue);
    expect(state.hint(), same(state));
  });

  test('the clock only runs forwards', () {
    final state = TangramState.initial(puzzle).tick(5);
    expect(state.elapsedSeconds, 5);
    expect(state.tick(0), same(state));
    expect(state.tick(1).elapsedSeconds, 6);
  });

  test('progress survives a round trip through json', () {
    var state = solvedExcept(TangramPiece.square).select(TangramPiece.mediumTriangle);
    state = state.nudge(1, 0).hint().tick(93);
    final restored = TangramState.fromJson(puzzle, state.toJson());
    expect(restored.placed, state.placed);
    expect(restored.selected, state.selected);
    expect(restored.hints, state.hints);
    expect(restored.elapsedSeconds, state.elapsedSeconds);
    expect(restored.undoStack, hasLength(state.undoStack.length));
    expect(restored.undo().placed, state.undo().placed);
  });

  test('the undo stack has a ceiling', () {
    var state = TangramState.initial(puzzle).place(TangramPiece.square, 4, 4);
    for (var i = 0; i < TangramState.maxUndo + 20; i++) {
      state = state.nudge(i.isEven ? 1 : -1, 0);
    }
    expect(state.undoStack, hasLength(TangramState.maxUndo));
  });

  test('rejects saved progress that is not this game', () {
    expect(() => TangramState.fromJson(puzzle, const {}), throwsFormatException);
    expect(() => TangramState.fromJson(puzzle, {'placed': 'nope'}), throwsFormatException);
    expect(
      () => TangramState.fromJson(puzzle, {
        'placed': [
          {'piece': 'square', 'x': 1, 'y': 1},
          {'piece': 'square', 'x': 2, 'y': 2},
        ]
      }),
      throwsFormatException,
    );
    expect(
      () => TangramState.fromJson(puzzle, {
        'placed': [
          {'piece': 'largeTriangleA', 'x': 0, 'y': 0}
        ]
      }),
      throwsFormatException,
    );
    expect(() => TangramState.fromJson(puzzle, {'placed': const [], 'hints': -1}), throwsFormatException);
  });
}
