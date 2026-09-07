import 'dart:convert';

import 'package:daypencil/engines/sudoku/sudoku.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = SudokuPuzzle.parse({'givens': singlesOnlyGivens}, {'solution': singlesOnlySolution});
  final blank = puzzle.givens.indexOf(0);
  final answer = puzzle.solution[blank];
  final wrong = answer == 9 ? 1 : answer + 1;
  final given = puzzle.givens.indexWhere((g) => g != 0);

  test('initial state mirrors the givens', () {
    final s = SudokuState.initial(puzzle);
    expect(s.values, puzzle.givens);
    expect(s.notes.every((n) => n.isEmpty), isTrue);
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isFalse);
    expect(s.selected, isNull);
    expect(s.notesMode, isFalse);
    expect(s.isSolved, isFalse);
    expect(s.isFull, isFalse);
    expect(s.wrongCells(), isEmpty);
    expect(s.conflicts(), isEmpty);
    final remaining = s.remainingCounts();
    expect(remaining.length, 10);
    expect(remaining.skip(1).reduce((a, b) => a + b), 81 - puzzle.givenCount);
  });

  test('values need a selected, editable cell', () {
    var s = SudokuState.initial(puzzle);
    expect(identical(s.setValue(5), s), isTrue);
    s = s.select(given);
    expect(identical(s.setValue(5), s), isTrue);
    expect(identical(s.erase(), s), isTrue);
    expect(identical(s.hint(), s), isTrue);
    expect(identical(s.toggleNote(3), s), isTrue);
    expect(() => s.select(81), throwsRangeError);
    expect(() => s.select(blank).setValue(0), throwsRangeError);
    expect(() => s.select(blank).toggleNote(10), throwsRangeError);
  });

  test('setting a value clears notes and undo and redo replay it', () {
    final start = SudokuState.initial(puzzle).select(blank).toggleNote(1).toggleNote(4);
    expect(start.notesAt(blank), {1, 4});
    expect(start.hasNote(blank, 4), isTrue);
    expect(start.values[blank], 0);

    final placed = start.setValue(answer);
    expect(placed.values[blank], answer);
    expect(placed.notesAt(blank), isEmpty);
    expect(placed.canUndo, isTrue);
    expect(placed.canRedo, isFalse);
    expect(identical(placed.setValue(answer), placed), isTrue);

    final undone = placed.undo();
    expect(undone.values[blank], 0);
    expect(undone.notesAt(blank), {1, 4});
    expect(undone.canRedo, isTrue);
    expect(undone.selected, blank);

    final redone = undone.redo();
    expect(redone.values[blank], answer);
    expect(redone.notesAt(blank), isEmpty);
    expect(redone.canRedo, isFalse);

    final branched = undone.toggleNote(1);
    expect(branched.canRedo, isFalse, reason: 'a new edit clears the redo stack');
    expect(branched.notesAt(blank), {4});
    expect(identical(SudokuState.initial(puzzle).undo(), SudokuState.initial(puzzle)), isFalse);
    expect(SudokuState.initial(puzzle).undo().values, puzzle.givens);
  });

  test('notes are only for empty cells and input follows notes mode', () {
    var s = SudokuState.initial(puzzle).select(blank).setValue(answer);
    expect(identical(s.toggleNote(2), s), isTrue);
    s = s.erase().toggleNotesMode();
    expect(s.notesMode, isTrue);
    s = s.input(2);
    expect(s.notesAt(blank), {2});
    expect(s.values[blank], 0);
    s = s.toggleNotesMode().input(answer);
    expect(s.values[blank], answer);
    expect(s.notesAt(blank), isEmpty);
  });

  test('erase clears value and notes, and is a no-op on an empty cell', () {
    var s = SudokuState.initial(puzzle).select(blank).setValue(answer);
    s = s.erase();
    expect(s.values[blank], 0);
    expect(identical(s.erase(), s), isTrue);
    s = s.toggleNote(7).erase();
    expect(s.notesAt(blank), isEmpty);
    expect(s.undo().notesAt(blank), {7});
  });

  test('hint fills the solution value and counts', () {
    var s = SudokuState.initial(puzzle).select(blank).setValue(wrong).toggleNotesMode();
    expect(s.wrongCells(), {blank});
    s = s.hint();
    expect(s.values[blank], answer);
    expect(s.hints, 1);
    expect(s.wrongCells(), isEmpty);
    expect(s.undo().values[blank], wrong, reason: 'a hint is undoable');
    expect(s.undo().hints, 1, reason: 'undo does not refund a hint');
    final again = s.hint();
    expect(again.hints, 2);
    expect(again.undoStack.length, s.undoStack.length, reason: 'nothing changed, no move recorded');
  });

  test('mistakes, conflicts and timing', () {
    var s = SudokuState.initial(puzzle).recordMistake().recordMistake();
    expect(s.mistakes, 2);
    s = s.tick(5).tick(0).tick(7);
    expect(s.elapsedSeconds, 12);
    final rowStart = (blank ~/ 9) * 9;
    final rowGiven = List.generate(9, (c) => rowStart + c).firstWhere((i) => puzzle.isGiven(i));
    s = s.select(blank).setValue(puzzle.givens[rowGiven]);
    expect(s.conflicts(), containsAll([blank, rowGiven]));
    expect(s.wrongCells(), {blank});
  });

  test('isSolved when every cell matches the solution', () {
    var s = SudokuState.initial(puzzle);
    for (var i = 0; i < 81; i++) {
      if (!puzzle.isGiven(i)) s = s.select(i).setValue(puzzle.solution[i]);
    }
    expect(s.isFull, isTrue);
    expect(s.isSolved, isTrue);
    expect(s.remainingCounts().skip(1).every((n) => n == 0), isTrue);
    final off = s.select(blank).setValue(wrong);
    expect(off.isFull, isTrue);
    expect(off.isSolved, isFalse);
  });

  test('progress survives a JSON round trip', () {
    final s = SudokuState.initial(puzzle)
        .select(blank)
        .toggleNote(3)
        .toggleNote(8)
        .setValue(wrong)
        .undo()
        .recordMistake()
        .tick(90)
        .toggleNotesMode()
        .hint();
    final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final back = SudokuState.fromJson(puzzle, json);
    expect(back.values, s.values);
    expect(back.notes, s.notes);
    expect(back.undoStack.map((m) => m.toJson()), s.undoStack.map((m) => m.toJson()));
    expect(back.redoStack.map((m) => m.toJson()), s.redoStack.map((m) => m.toJson()));
    expect(back.mistakes, 1);
    expect(back.hints, 1);
    expect(back.elapsedSeconds, 90);
    expect(back.selected, blank);
    expect(back.notesMode, isTrue);
    expect(back.canRedo, s.canRedo);
    expect(back.undo().values, s.undo().values);
  });

  test('fromJson rejects progress that does not fit the puzzle', () {
    final json = SudokuState.initial(puzzle).toJson();
    expect(() => SudokuState.fromJson(puzzle, {...json, 'values': '0' * 81}), throwsFormatException);
    expect(() => SudokuState.fromJson(puzzle, {...json, 'values': '1'}), throwsFormatException);
    expect(() => SudokuState.fromJson(puzzle, {...json, 'notes': [1]}), throwsFormatException);
    expect(() => SudokuState.fromJson(puzzle, {...json, 'undo': [[1, 2]]}), throwsFormatException);
    expect(() => SudokuState.fromJson(puzzle, {...json, 'selected': 81}), throwsFormatException);
    expect(() => SudokuState.fromJson(puzzle, {...json, 'hints': -1}), throwsFormatException);
    expect(() => SudokuState.fromJson(puzzle, {}), throwsFormatException);
    final minimal = SudokuState.fromJson(puzzle, {'values': singlesOnlyGivens, 'notes': List.filled(81, 0)});
    expect(minimal.elapsedSeconds, 0);
    expect(minimal.canUndo, isFalse);
  });
}
