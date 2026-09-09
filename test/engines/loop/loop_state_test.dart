import 'dart:convert';

import 'package:playthepaper/engines/loop/loop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = LoopPuzzle.parse(smallPayload(clues: smallSparseClues), smallReveal());
  final grid = puzzle.grid;
  final onLoop = grid.h(0, 0);
  final offLoop = grid.h(0, 2);

  LoopState solvedButOne(int missing) {
    var s = LoopState.initial(puzzle);
    for (var e = 0; e < grid.edgeCount; e++) {
      if (puzzle.solution[e] && e != missing) s = s.toggleLine(e);
    }
    return s;
  }

  test('initial state is empty', () {
    final s = LoopState.initial(puzzle);
    expect(s.marks.every((m) => m == EdgeMark.empty), isTrue);
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isFalse);
    expect(s.cursor, isNull);
    expect(s.crossMode, isFalse);
    expect(s.hasLines, isFalse);
    expect(s.isSolved, isFalse);
    expect(s.violation, contains('clue says 2'));
    expect(s.hints, 0);
    expect(s.elapsedSeconds, 0);
    expect(s.satisfiedCells(), {grid.cell(2, 0)});
    expect(s.brokenCells(), isEmpty);
    expect(s.branchDots(), isEmpty);
  });

  test('lines and crosses toggle and replace each other', () {
    var s = LoopState.initial(puzzle).toggleLine(onLoop);
    expect(s.markAt(onLoop), EdgeMark.line);
    expect(s.hasLines, isTrue);
    s = s.toggleCross(onLoop);
    expect(s.markAt(onLoop), EdgeMark.cross);
    s = s.toggleCross(onLoop);
    expect(s.markAt(onLoop), EdgeMark.empty);
    s = s.toggleCross(onLoop).toggleLine(onLoop);
    expect(s.markAt(onLoop), EdgeMark.line);
    s = s.toggleLine(onLoop);
    expect(s.markAt(onLoop), EdgeMark.empty);
    expect(identical(s.setMark(onLoop, EdgeMark.empty), s), isTrue);
    expect(() => s.toggleLine(grid.edgeCount), throwsRangeError);
    expect(() => s.select(-1), throwsRangeError);
  });

  test('tap follows the mode and moves the cursor', () {
    var s = LoopState.initial(puzzle).tap(onLoop);
    expect(s.markAt(onLoop), EdgeMark.line);
    expect(s.cursor, onLoop);
    s = s.toggleCrossMode();
    expect(s.crossMode, isTrue);
    s = s.tap(offLoop);
    expect(s.markAt(offLoop), EdgeMark.cross);
    expect(s.cursor, offLoop);
    s = s.tap(onLoop);
    expect(s.markAt(onLoop), EdgeMark.cross);
    expect(s.select(null).cursor, isNull);
  });

  test('undo and redo replay moves and a new move clears redo', () {
    final start = LoopState.initial(puzzle).toggleLine(onLoop).toggleCross(offLoop);
    expect(start.undoStack.length, 2);
    final undone = start.undo();
    expect(undone.markAt(offLoop), EdgeMark.empty);
    expect(undone.markAt(onLoop), EdgeMark.line);
    expect(undone.canRedo, isTrue);
    expect(undone.cursor, offLoop);
    final redone = undone.redo();
    expect(redone.markAt(offLoop), EdgeMark.cross);
    expect(redone.canRedo, isFalse);
    final branched = undone.toggleLine(grid.v(0, 0));
    expect(branched.canRedo, isFalse);
    expect(identical(LoopState.initial(puzzle).undo(), LoopState.initial(puzzle)), isFalse);
    expect(LoopState.initial(puzzle).undo().marks, LoopState.initial(puzzle).marks);
    expect(identical(branched.redo(), branched), isTrue);
  });

  test('counts and flags follow the marks', () {
    var s = LoopState.initial(puzzle);
    final cell = grid.cell(1, 2);
    for (final e in grid.cellEdges[cell]) {
      s = s.toggleLine(e);
    }
    expect(s.cellLineCount(cell), 4);
    expect(s.brokenCells(), contains(cell));
    expect(s.satisfiedCells(), isNot(contains(cell)));
    s = s.toggleLine(grid.h(1, 2));
    expect(s.cellLineCount(cell), 3);
    expect(s.satisfiedCells(), contains(cell));
    expect(s.brokenCells(), isNot(contains(cell)));
    expect(s.dotDegree(grid.dot(2, 3)), 2);

    var crossed = LoopState.initial(puzzle);
    for (final e in grid.cellEdges[cell].take(2)) {
      crossed = crossed.toggleCross(e);
    }
    expect(crossed.brokenCells(), contains(cell), reason: 'two crosses leave room for only two lines under a 3');

    final branch = LoopState.initial(puzzle).toggleLine(grid.h(1, 0)).toggleLine(grid.h(1, 1)).toggleLine(grid.v(0, 1));
    expect(branch.branchDots(), {grid.dot(1, 1)});
    expect(branch.violation, contains('three or more'));
  });

  test('is solved only by the one loop, crosses ignored', () {
    final almost = solvedButOne(onLoop);
    expect(almost.isSolved, isFalse);
    expect(almost.violation, contains('open'));
    final done = almost.toggleLine(onLoop);
    expect(done.isSolved, isTrue);
    expect(done.violation, isNull);
    expect(done.toggleCross(offLoop).isSolved, isTrue);
    expect(done.toggleLine(offLoop).isSolved, isFalse);
    var two = LoopState.initial(puzzle);
    for (final e in [...grid.cellEdges[grid.cell(0, 0)], ...grid.cellEdges[grid.cell(2, 2)]]) {
      two = two.toggleLine(e);
    }
    expect(two.isSolved, isFalse);
    expect(two.violation, isNotNull);
    expect(LoopRules.violation(grid, List.filled(grid.cellCount, -1), two.lines), 'more than one loop');
  });

  test('hints fix a wrong mark first, then a forced edge, and are counted', () {
    final wrong = LoopState.initial(puzzle).toggleLine(offLoop).toggleCross(onLoop);
    final fixed = wrong.hint();
    expect(fixed.hints, 1);
    expect(fixed.markAt(onLoop), EdgeMark.line);
    expect(fixed.cursor, onLoop);
    expect(fixed.canUndo, isTrue);
    final fixedAgain = fixed.hint();
    expect(fixedAgain.markAt(offLoop), EdgeMark.cross);
    expect(fixedAgain.hints, 2);

    final zero = grid.cell(2, 0);
    final forced = LoopState.initial(puzzle).hint();
    expect(forced.hints, 1);
    final edge = forced.undoStack.single.edge;
    expect(forced.markAt(edge), puzzle.solution[edge] ? EdgeMark.line : EdgeMark.cross);
    expect(forced.hintEdge(), isNot(edge));
    var s = LoopState.initial(puzzle);
    while (!s.isSolved) {
      s = s.hint();
    }
    expect(s.hints, lessThanOrEqualTo(grid.edgeCount));
    expect(s.isSolved, isTrue);
    expect(identical(s.hint(), s), isTrue);
    expect(s.hintEdge(), isNull);
    expect(grid.cellEdges[zero].every((e) => s.markAt(e) != EdgeMark.line), isTrue);
  });

  test('a hint prefers a line the loop must take', () {
    final s = LoopState.initial(puzzle).toggleLine(grid.h(0, 0)).hint();
    final edge = s.undoStack.last.edge;
    final forced = LoopSolver.propagate(grid, puzzle.clues, List.filled(grid.edgeCount, LoopSolver.unknown)..[grid.h(0, 0)] = 1)!;
    expect(forced[edge], 1, reason: 'the counting rules force this line');
    expect(s.markAt(edge), EdgeMark.line);
    expect(puzzle.solution[edge], isTrue);
  });

  test('tick accumulates time', () {
    final s = LoopState.initial(puzzle).tick(3).tick(4);
    expect(s.elapsedSeconds, 7);
    expect(identical(s.tick(0), s), isTrue);
  });

  test('progress survives a JSON round trip', () {
    final s = LoopState.initial(puzzle)
        .tap(onLoop)
        .toggleCrossMode()
        .tap(offLoop)
        .toggleLine(grid.v(1, 1))
        .undo()
        .hint()
        .tick(42);
    final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final back = LoopState.fromJson(puzzle, json);
    expect(back.marks, s.marks);
    expect(back.undoStack.length, s.undoStack.length);
    expect(back.redoStack.length, s.redoStack.length);
    expect(back.hints, 1);
    expect(back.elapsedSeconds, 42);
    expect(back.cursor, s.cursor);
    expect(back.crossMode, isTrue);
    expect(back.undo().marks, s.undo().marks);
    expect(back.toJson(), s.toJson());
  });

  test('malformed progress is rejected', () {
    final good = LoopState.initial(puzzle).toggleLine(onLoop).toJson();
    expect(LoopState.fromJson(puzzle, {'marks': good['marks']}).markAt(onLoop), EdgeMark.line);
    expect(() => LoopState.fromJson(puzzle, {}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'marks': '-'}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'marks': (good['marks'] as String).replaceFirst('-', '?')}),
        throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'undo': 'x'}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'undo': [[1, 2]]}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'undo': [[grid.edgeCount, 0, 1]]}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'redo': [[0, 0, 3]]}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'hints': -1}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'elapsed': 'soon'}), throwsFormatException);
    expect(() => LoopState.fromJson(puzzle, {...good, 'cursor': grid.edgeCount}), throwsFormatException);
  });
}
