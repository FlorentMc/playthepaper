import 'package:playthepaper/engines/nonogram/nonogram.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = crossPuzzle();

  NonogramState solvedState() {
    var state = NonogramState.initial(puzzle);
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (puzzle.isFilled(i)) state = state.set(i, CellMark.filled);
    }
    return state;
  }

  test('a fresh state is blank, unsolved and has no history', () {
    final state = NonogramState.initial(puzzle);
    expect(state.cells.length, 25);
    expect(state.isEmpty, isTrue);
    expect(state.isSolved, isFalse);
    expect(state.canUndo, isFalse);
    expect(state.canRedo, isFalse);
    expect(state.hints, 0);
    expect(state.elapsedSeconds, 0);
    expect(state.cursor, isNull);
    expect(state.mode, PaintMode.fill);
  });

  test('a tap cycles blank, filled, crossed, blank', () {
    var state = NonogramState.initial(puzzle);
    expect(state.markAt(0), CellMark.unknown);
    state = state.cycle(0);
    expect(state.markAt(0), CellMark.filled);
    state = state.cycle(0);
    expect(state.markAt(0), CellMark.crossed);
    state = state.cycle(0);
    expect(state.markAt(0), CellMark.unknown);
  });

  test('setting a cell to what it already holds changes nothing', () {
    final state = NonogramState.initial(puzzle);
    expect(identical(state.set(0, CellMark.unknown), state), isTrue);
  });

  test('toggle clears a cell that already holds the mark', () {
    var state = NonogramState.initial(puzzle).toggle(3, CellMark.crossed);
    expect(state.markAt(3), CellMark.crossed);
    state = state.toggle(3, CellMark.crossed);
    expect(state.markAt(3), CellMark.unknown);
  });

  test('an out-of-range cell throws', () {
    final state = NonogramState.initial(puzzle);
    expect(() => state.cycle(25), throwsRangeError);
    expect(() => state.cycle(-1), throwsRangeError);
    expect(() => state.checkRow(5), throwsRangeError);
  });

  test('undo and redo step one edit at a time', () {
    var state = NonogramState.initial(puzzle).cycle(0).cycle(1);
    expect(state.canUndo, isTrue);
    state = state.undo();
    expect(state.markAt(1), CellMark.unknown);
    expect(state.markAt(0), CellMark.filled);
    expect(state.canRedo, isTrue);
    state = state.redo();
    expect(state.markAt(1), CellMark.filled);
    expect(state.canRedo, isFalse);
  });

  test('a stroke of several cells undoes as one step', () {
    var state = NonogramState.initial(puzzle);
    state = state.set(0, CellMark.filled);
    state = state.set(1, CellMark.filled, extendStroke: true);
    state = state.set(2, CellMark.filled, extendStroke: true);
    expect(state.undoStack.length, 1);
    state = state.undo();
    expect(state.isEmpty, isTrue);
  });

  test('a new edit clears the redo stack', () {
    final state = NonogramState.initial(puzzle).cycle(0).undo().cycle(4);
    expect(state.canRedo, isFalse);
  });

  test('strokeTarget follows the mode and clears a cell that matches', () {
    var state = NonogramState.initial(puzzle);
    expect(state.strokeTarget(0), CellMark.filled);
    state = state.set(0, CellMark.filled);
    expect(state.strokeTarget(0), CellMark.unknown);
    state = state.setMode(PaintMode.cross);
    expect(state.strokeTarget(0), CellMark.crossed);
    expect(state.toggleMode().mode, PaintMode.fill);
    expect(identical(state.setMode(PaintMode.cross), state), isTrue);
  });

  test('the cursor moves and clamps to the board', () {
    var state = NonogramState.initial(puzzle);
    state = state.moveCursor(0, 1);
    expect(state.cursor, 0, reason: 'the first move places the cursor');
    state = state.moveCursor(0, 1);
    expect(state.cursor, 1);
    state = state.moveCursor(1, 0);
    expect(state.cursor, 6);
    expect(state.cursorRow, 1);
    state = state.moveCursor(-5, -5);
    expect(state.cursor, 0);
    state = state.moveCursor(9, 9);
    expect(state.cursor, 24);
    expect(state.setCursor(null).cursor, isNull);
    expect(() => state.setCursor(25), throwsRangeError);
  });

  test('a row is satisfied only when its filled cells read as its clue', () {
    var state = NonogramState.initial(puzzle);
    expect(state.rowSatisfied(0), isFalse);
    state = state.set(1, CellMark.filled).set(2, CellMark.filled).set(3, CellMark.filled);
    expect(state.rowSatisfied(0), isTrue);
    expect(state.columnSatisfied(2), isFalse);
    state = state.set(0, CellMark.crossed).set(4, CellMark.crossed);
    expect(state.rowSatisfied(0), isTrue, reason: 'crosses are not filled cells');
  });

  test('isSolved ignores crosses and blanks alike', () {
    var state = solvedState();
    expect(state.isSolved, isTrue);
    state = state.set(0, CellMark.crossed);
    expect(state.isSolved, isTrue);
    state = state.set(1, CellMark.crossed);
    expect(state.isSolved, isFalse, reason: 'a filled cell was taken away');
  });

  test('a check names the wrong cells in a row and counts a hint', () {
    var state = NonogramState.initial(puzzle).set(0, CellMark.filled).set(1, CellMark.crossed);
    expect(state.wrongInRow(0), {0, 1});
    state = state.checkRow(0);
    expect(state.flagged, {0, 1});
    expect(state.hints, 1);
    state = state.set(0, CellMark.unknown);
    expect(state.flagged, {1}, reason: 'a flag clears when its cell changes');
    expect(state.checkRow(1).hints, 2);
  });

  test('a check finds nothing wrong in a correct row', () {
    final state = NonogramState.initial(puzzle).set(1, CellMark.filled).set(0, CellMark.crossed);
    expect(state.wrongInRow(0), isEmpty);
    expect(state.checkRow(0).flagged, isEmpty);
    expect(state.checkRow(0).hints, 1);
  });

  test('reset clears the marks, the history and the flags but keeps time and hints', () {
    final state = NonogramState.initial(puzzle).tick(30).cycle(0).checkRow(0).reset();
    expect(state.isEmpty, isTrue);
    expect(state.canUndo, isFalse);
    expect(state.canRedo, isFalse);
    expect(state.flagged, isEmpty);
    expect(state.elapsedSeconds, 30);
    expect(state.hints, 1);
    expect(identical(state.reset(), state), isTrue);
  });

  test('the clock adds up and a zero tick changes nothing', () {
    final state = NonogramState.initial(puzzle).tick(5).tick(7);
    expect(state.elapsedSeconds, 12);
    expect(identical(state.tick(0), state), isTrue);
  });

  test('progress round trips through json', () {
    final state = NonogramState.initial(puzzle)
        .cycle(0)
        .set(1, CellMark.filled)
        .set(2, CellMark.filled, extendStroke: true)
        .cycle(7)
        .cycle(7)
        .undo()
        .checkRow(0)
        .setMode(PaintMode.cross)
        .setCursor(9)
        .tick(64);
    final json = state.toJson();
    final back = NonogramState.fromJson(puzzle, json);
    expect(back.cells, state.cells);
    expect(back.hints, state.hints);
    expect(back.elapsedSeconds, 64);
    expect(back.cursor, 9);
    expect(back.mode, PaintMode.cross);
    expect(back.flagged, isNotEmpty);
    expect(back.flagged, state.flagged);
    expect(back.canUndo, state.canUndo);
    expect(back.canRedo, state.canRedo);
    expect(back.toJson(), json);
    expect(back.undo().cells, state.undo().cells);
    expect(back.redo().cells, state.redo().cells);
  });

  group('progress json rejects', () {
    final good = NonogramState.initial(puzzle).cycle(0).checkRow(0).toJson();

    Map<String, dynamic> with_(Map<String, dynamic> changes) => {...good, ...changes};

    test('the wrong number of cells', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'cells': '###'})), throwsFormatException);
    });

    test('an unknown cell symbol', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'cells': '?' * 25})), throwsFormatException);
    });

    test('a negative hint count', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'hints': -1})), throwsFormatException);
    });

    test('a negative elapsed time', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'elapsed': -5})), throwsFormatException);
    });

    test('a cursor off the board', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'cursor': 25})), throwsFormatException);
    });

    test('a flag off the board', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'flagged': [99]})), throwsFormatException);
    });

    test('a malformed change', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'undo': [[[0, '#']]]})), throwsFormatException);
    });

    test('a change naming a cell off the board', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'undo': [[[40, '.', '#']]]})), throwsFormatException);
    });

    test('an empty stroke', () {
      expect(() => NonogramState.fromJson(puzzle, with_({'undo': [[]]})), throwsFormatException);
    });
  });
}
