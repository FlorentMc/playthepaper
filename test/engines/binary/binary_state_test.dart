import 'dart:convert';

import 'package:playthepaper/engines/binary/binary.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = BinaryPuzzle.parse({'size': 6, 'givens': givens6}, {'solution': solution6});
  final blank = puzzle.givens.indexOf(BinaryRules.empty);
  final answer = puzzle.solution[blank];
  final given = puzzle.givens.indexWhere((g) => g != BinaryRules.empty);

  test('initial state mirrors the givens', () {
    final s = BinaryState.initial(puzzle);
    expect(s.values, puzzle.givens);
    expect(s.size, 6);
    expect(s.canUndo, isFalse);
    expect(s.selected, isNull);
    expect(s.hints, 0);
    expect(s.flagged, isEmpty);
    expect(s.isSolved, isFalse);
    expect(s.isFull, isFalse);
    expect(s.wrongCells(), isEmpty);
    expect(s.conflicts(), isEmpty);
    expect(s.remainingIn(BinaryRules.rows(6)[0]), [1, 0]);
    expect(s.remainingIn(BinaryRules.rows(6)[1]), [1, 2]);
  });

  test('tap cycles empty, filled, hollow, empty and leaves givens alone', () {
    var s = BinaryState.initial(puzzle);
    s = s.cycle(blank);
    expect(s.values[blank], 1);
    expect(s.selected, blank);
    s = s.cycle(blank);
    expect(s.values[blank], 0);
    s = s.cycle(blank);
    expect(s.values[blank], BinaryRules.empty);
    expect(s.undoStack.length, 3);

    final before = s;
    s = s.cycle(given);
    expect(s.values[given], puzzle.givens[given]);
    expect(s.undoStack.length, before.undoStack.length);
    expect(s.selected, given);
  });

  test('setValue validates and ignores no-op edits', () {
    final s = BinaryState.initial(puzzle);
    expect(() => s.setValue(-1, 1), throwsRangeError);
    expect(() => s.setValue(36, 1), throwsRangeError);
    expect(() => s.setValue(blank, 2), throwsRangeError);
    expect(() => s.select(36), throwsRangeError);
    final same = s.setValue(blank, BinaryRules.empty);
    expect(same.values, s.values);
    expect(same.canUndo, isFalse);
    expect(s.clear(blank).canUndo, isFalse);
  });

  test('undo restores the previous value and the selection', () {
    var s = BinaryState.initial(puzzle).setValue(blank, 1).select(null);
    expect(s.selected, isNull);
    s = s.undo();
    expect(s.values[blank], BinaryRules.empty);
    expect(s.selected, blank);
    expect(s.canUndo, isFalse);
    expect(identical(s.undo(), s), isTrue);
  });

  test('check flags wrong cells, counts a hint, and an edit clears the flag', () {
    final wrong = 1 - answer;
    var s = BinaryState.initial(puzzle).setValue(blank, wrong).check();
    expect(s.hints, 1);
    expect(s.flagged, {blank});
    expect(s.wrongCells(), {blank});
    s = s.setValue(blank, answer);
    expect(s.flagged, isEmpty);
    s = s.check();
    expect(s.hints, 2);
    expect(s.flagged, isEmpty);
    expect(s.setValue(blank, wrong).check().undo().flagged, isEmpty);
  });

  test('conflicts follow the rules as the grid stands', () {
    final size = 6;
    var s = BinaryState.initial(puzzle);
    final row1 = BinaryRules.rows(size)[1];
    for (final i in row1) {
      if (!puzzle.isGiven(i)) s = s.setValue(i, 0);
    }
    expect(s.conflicts(), isNotEmpty);
    expect(s.conflicts().every(row1.contains), isTrue);
    expect(s.conflicts(), s.conflicts().intersection(BinaryRules.overCountCells(s.values, size)));
  });

  test('a full grid that satisfies the rules is solved', () {
    var s = BinaryState.initial(puzzle);
    for (var i = 0; i < 36; i++) {
      if (!puzzle.isGiven(i)) s = s.setValue(i, puzzle.solution[i]);
    }
    expect(s.isFull, isTrue);
    expect(s.isSolved, isTrue);
    expect(s.conflicts(), isEmpty);
    final broken = s.setValue(blank, 1 - answer);
    expect(broken.isFull, isTrue);
    expect(broken.isSolved, isFalse);
    expect(broken.conflicts(), isNotEmpty);
  });

  test('progress round-trips through json', () {
    final s = BinaryState.initial(puzzle).setValue(blank, 1 - answer).check().tick(75).select(3);
    final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final back = BinaryState.fromJson(puzzle, json);
    expect(back.values, s.values);
    expect(back.undoStack.length, 1);
    expect(back.undoStack.first.cell, blank);
    expect(back.flagged, {blank});
    expect(back.hints, 1);
    expect(back.elapsedSeconds, 75);
    expect(back.selected, 3);
    expect(back.undo().values, puzzle.givens);
  });

  test('fromJson rejects malformed or foreign progress', () {
    final good = BinaryState.initial(puzzle).toJson();
    expect(() => BinaryState.fromJson(puzzle, {}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'values': 'x' * 36}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'values': '.' * 36}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'undo': [[0, 0]]}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'undo': [[99, 0, 1]]}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'flagged': [99]}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'hints': -1}), throwsFormatException);
    expect(() => BinaryState.fromJson(puzzle, {...good, 'selected': 36}), throwsFormatException);
    final minimal = BinaryState.fromJson(puzzle, {'values': givens6});
    expect(minimal.hints, 0);
    expect(minimal.canUndo, isFalse);
  });
}
