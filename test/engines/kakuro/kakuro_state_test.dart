import 'dart:convert';

import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = smallPuzzle();
  const first = 4;
  const clue = 1;

  test('initial state is empty', () {
    final s = KakuroState.initial(puzzle);
    expect(s.values, List.filled(9, 0));
    expect(s.notesAt(first), isEmpty);
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isFalse);
    expect(s.selected, isNull);
    expect(s.notesMode, isFalse);
    expect(s.isSolved, isFalse);
    expect(s.isFull, isFalse);
    expect(s.hints, 0);
    expect(s.wrong, isEmpty);
    expect(s.conflicts(), isEmpty);
    expect(s.runStatus(puzzle.runs[0]), RunStatus.open);
  });

  test('values need a selected white cell', () {
    var s = KakuroState.initial(puzzle);
    expect(identical(s.setValue(5), s), isTrue);
    s = s.select(clue);
    expect(s.canEditSelected, isFalse);
    expect(identical(s.setValue(5), s), isTrue);
    expect(identical(s.erase(), s), isTrue);
    expect(identical(s.revealCell(), s), isTrue);
    expect(identical(s.toggleNote(3), s), isTrue);
    expect(() => s.select(9), throwsRangeError);
    expect(() => s.select(first).setValue(0), throwsRangeError);
    expect(() => s.select(first).toggleNote(10), throwsRangeError);
    expect(s.select(first).canEditSelected, isTrue);
  });

  test('setting a value clears notes and undo and redo replay it', () {
    final start = KakuroState.initial(puzzle).select(first).toggleNote(1).toggleNote(4);
    expect(start.notesAt(first), {1, 4});
    expect(start.hasNote(first, 4), isTrue);
    expect(start.values[first], 0);

    final placed = start.setValue(1);
    expect(placed.values[first], 1);
    expect(placed.notesAt(first), isEmpty);
    expect(placed.canUndo, isTrue);
    expect(placed.canRedo, isFalse);
    expect(identical(placed.setValue(1), placed), isTrue);

    final undone = placed.undo();
    expect(undone.values[first], 0);
    expect(undone.notesAt(first), {1, 4});
    expect(undone.canRedo, isTrue);
    expect(undone.selected, first);

    final redone = undone.redo();
    expect(redone.values[first], 1);
    expect(redone.notesAt(first), isEmpty);
    expect(redone.canRedo, isFalse);

    final branched = undone.toggleNote(1);
    expect(branched.canRedo, isFalse, reason: 'a new edit clears the redo stack');
    expect(branched.notesAt(first), {4});
    expect(identical(KakuroState.initial(puzzle).undo(), KakuroState.initial(puzzle)), isFalse);
    expect(KakuroState.initial(puzzle).undo().values, List.filled(9, 0));
  });

  test('notes are only for empty cells and input follows notes mode', () {
    var s = KakuroState.initial(puzzle).select(first).setValue(3);
    expect(identical(s.toggleNote(2), s), isTrue);
    s = s.erase().toggleNotesMode();
    expect(s.notesMode, isTrue);
    s = s.input(2);
    expect(s.notesAt(first), {2});
    expect(s.values[first], 0);
    s = s.toggleNotesMode().input(1);
    expect(s.values[first], 1);
    expect(s.notesAt(first), isEmpty);
  });

  test('erase clears value and notes, and is a no-op on an empty cell', () {
    var s = KakuroState.initial(puzzle).select(first).setValue(2);
    s = s.erase();
    expect(s.values[first], 0);
    expect(identical(s.erase(), s), isTrue);
    s = s.toggleNote(7).erase();
    expect(s.notesAt(first), isEmpty);
    expect(s.undo().notesAt(first), {7});
  });

  test('conflicts and run status follow the rules, not the solution', () {
    var s = KakuroState.initial(puzzle).select(4).setValue(2).select(5).setValue(2);
    expect(s.conflicts(), {4, 5});
    expect(s.runStatus(puzzle.grid.runs[puzzle.grid.acrossRunOf[4]]), RunStatus.wrong);
    s = s.select(5).setValue(1);
    expect(s.conflicts(), isEmpty);
    expect(s.runStatus(puzzle.grid.runs[puzzle.grid.acrossRunOf[4]]), RunStatus.met, reason: '2 + 1 = 3');
    expect(s.runStatus(puzzle.grid.runs[puzzle.grid.downRunOf[4]]), RunStatus.open);
    expect(s.wrongCells(), {4, 5}, reason: 'the sum is met but the digits are swapped');
    s = s.select(7).setValue(9);
    expect(s.runStatus(puzzle.grid.runs[puzzle.grid.downRunOf[4]]), RunStatus.wrong);
  });

  test('check marks wrong cells, counts a hint, and editing clears the mark', () {
    var s = KakuroState.initial(puzzle).select(4).setValue(2).select(5).setValue(3).select(7).setValue(3);
    s = s.check();
    expect(s.hints, 1);
    expect(s.wrong, {4, 5});
    s = s.select(4).setValue(1);
    expect(s.wrong, {5});
    expect(s.hints, 1);
    s = s.undo();
    expect(s.wrong, {5}, reason: 'undo of another cell keeps the mark');
    expect(s.values[4], 2);
    s = s.select(5).erase();
    expect(s.wrong, isEmpty);
    expect(s.check().hints, 2);
    expect(s.check().wrong, {4});
  });

  test('reveal fills the solution value and counts', () {
    var s = KakuroState.initial(puzzle).select(first).setValue(9).check();
    expect(s.wrong, {first});
    s = s.revealCell();
    expect(s.values[first], puzzle.solution[first]);
    expect(s.hints, 2);
    expect(s.wrong, isEmpty);
    expect(s.undo().values[first], 9, reason: 'a reveal is undoable');
    expect(s.undo().hints, 2, reason: 'undo does not refund a hint');
    final again = s.revealCell();
    expect(again.hints, 3);
    expect(again.undoStack.length, s.undoStack.length, reason: 'nothing changed, no move recorded');
  });

  test('isSolved follows the rules and timing accumulates', () {
    var s = KakuroState.initial(puzzle).tick(5).tick(0).tick(7);
    expect(s.elapsedSeconds, 12);
    for (final w in puzzle.whiteCells) {
      s = s.select(w).setValue(puzzle.solution[w]);
    }
    expect(s.isFull, isTrue);
    expect(s.isSolved, isTrue);
    for (final run in puzzle.runs) {
      expect(s.runStatus(run), RunStatus.met);
    }
    final off = s.select(8).setValue(2);
    expect(off.isFull, isTrue);
    expect(off.isSolved, isFalse);
  });

  test('progress survives a JSON round trip', () {
    final s = KakuroState.initial(puzzle)
        .select(first)
        .toggleNote(3)
        .toggleNote(8)
        .setValue(7)
        .undo()
        .select(5)
        .setValue(9)
        .check()
        .tick(90)
        .toggleNotesMode()
        .select(7)
        .revealCell()
        .select(5)
        .setValue(2)
        .undo();
    final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final back = KakuroState.fromJson(puzzle, json);
    expect(back.values, s.values);
    for (final w in puzzle.whiteCells) {
      expect(back.notesAt(w), s.notesAt(w));
    }
    expect(back.notesAt(first), {3, 8});
    expect(back.values[5], 9);
    expect(back.values[7], 3);
    expect(back.undoStack.map((m) => m.toJson()), s.undoStack.map((m) => m.toJson()));
    expect(back.redoStack.map((m) => m.toJson()), s.redoStack.map((m) => m.toJson()));
    expect(back.wrong, s.wrong);
    expect(back.hints, 2);
    expect(back.elapsedSeconds, 90);
    expect(back.selected, 5);
    expect(back.notesMode, isTrue);
    expect(back.canRedo, isTrue);
    expect(back.redo().values, s.redo().values);
    expect(back.undo().values, s.undo().values);
  });

  test('fromJson rejects progress that does not fit the puzzle', () {
    final json = KakuroState.initial(puzzle).toJson();
    expect(() => KakuroState.fromJson(puzzle, {...json, 'values': List.filled(8, 0)}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'values': List.filled(9, 1)}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'values': [0, 0, 0, 0, 10, 0, 0, 0, 0]}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'notes': [1]}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'undo': [[1, 2]]}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'undo': [[0, 0, 0, 1, 0]]}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'wrong': [9]}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'selected': 9}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {...json, 'hints': -1}), throwsFormatException);
    expect(() => KakuroState.fromJson(puzzle, {}), throwsFormatException);
    final minimal = KakuroState.fromJson(puzzle, {'values': List.filled(9, 0), 'notes': List.filled(9, 0)});
    expect(minimal.elapsedSeconds, 0);
    expect(minimal.canUndo, isFalse);
    expect(minimal.wrong, isEmpty);
  });
}
