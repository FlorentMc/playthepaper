import 'package:playthepaper/engines/regions/regions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = tinyPuzzle();

  test('starts from the givens with nothing selected', () {
    final s = RegionsState.initial(puzzle);
    expect(s.values, puzzle.givens);
    expect(s.selected, isNull);
    expect(s.canUndo, isFalse);
    expect(s.isFull, isFalse);
    expect(s.isSolved, isFalse);
    expect(s.hasEntries, isFalse);
    expect(s.hints, 0);
    expect(s.notesMode, isFalse);
    expect(s.canEditSelected, isFalse);
    expect(s.conflicts(), isEmpty);
  });

  test('places, erases and undoes values in the selected cell', () {
    var s = RegionsState.initial(puzzle).select(0);
    expect(s.canEditSelected, isTrue);
    s = s.setValue(3);
    expect(s.values[0], 3);
    expect(s.hasEntries, isTrue);
    expect(s.canUndo, isTrue);
    expect(identical(s.setValue(3), s), isTrue);
    s = s.setValue(1);
    expect(s.values[0], 1);
    s = s.erase();
    expect(s.values[0], 0);
    s = s.undo();
    expect(s.values[0], 1);
    s = s.undo();
    expect(s.values[0], 3);
    s = s.undo();
    expect(s.values[0], 0);
    expect(s.canUndo, isFalse);
    expect(identical(s.undo(), s), isTrue);
  });

  test('givens cannot change and digits above the region size are ignored', () {
    var s = RegionsState.initial(puzzle).select(2);
    expect(s.canEditSelected, isFalse);
    expect(identical(s.setValue(4), s), isTrue);
    expect(identical(s.erase(), s), isTrue);
    expect(identical(s.reveal(), s), isTrue);
    s = s.select(0);
    expect(identical(s.setValue(5), s), isTrue);
    expect(identical(s.toggleNote(5), s), isTrue);
    expect(() => s.setValue(6), throwsRangeError);
    expect(() => s.setValue(0), throwsRangeError);
    expect(() => s.select(8), throwsRangeError);
    expect(identical(RegionsState.initial(puzzle).setValue(1), RegionsState.initial(puzzle)), isFalse);
    expect(RegionsState.initial(puzzle).setValue(1).values, puzzle.givens);
  });

  test('notes toggle in empty cells and clear when a value is placed', () {
    var s = RegionsState.initial(puzzle).select(0).toggleNotesMode();
    expect(s.notesMode, isTrue);
    s = s.input(1).input(3);
    expect(s.notesAt(0), {1, 3});
    expect(s.hasNote(0, 3), isTrue);
    s = s.input(3);
    expect(s.notesAt(0), {1});
    s = s.toggleNotesMode().input(2);
    expect(s.values[0], 2);
    expect(s.notesAt(0), isEmpty);
    expect(identical(s.toggleNote(1), s), isTrue);
    s = s.undo();
    expect(s.values[0], 0);
    expect(s.notesAt(0), {1});
  });

  test('conflicts follow the rules: touching equals and repeats in a region', () {
    var s = RegionsState.initial(puzzle).select(0).setValue(3);
    expect(s.conflicts(), {0, 4});
    s = s.select(1).setValue(1);
    expect(s.conflicts(), {0, 1, 2, 4});
    s = s.setValue(2);
    expect(s.conflicts(), {0, 4});
    s = s.select(0).setValue(1);
    expect(s.conflicts(), isEmpty);
  });

  test('check marks wrong digits and counts a hint; editing clears the mark', () {
    var s = RegionsState.initial(puzzle).select(0).setValue(2).select(1).setValue(2).select(6).setValue(3);
    expect(s.wrongCells(), {0});
    s = s.check();
    expect(s.flagged, {0});
    expect(s.hints, 1);
    s = s.select(0).setValue(1);
    expect(s.flagged, isEmpty);
    s = s.check();
    expect(s.flagged, isEmpty);
    expect(s.hints, 2);
  });

  test('reveal fills the selected cell with its answer and counts a hint', () {
    var s = RegionsState.initial(puzzle).select(0).reveal();
    expect(s.values[0], 1);
    expect(s.hints, 1);
    expect(s.revealed, {0});
    s = s.reveal();
    expect(s.hints, 2);
    expect(s.canUndo, isTrue);
    s = s.undo();
    expect(s.values[0], 0);
    expect(s.revealed, isEmpty);
    expect(s.hints, 2);
  });

  test('isSolved holds when the board obeys every rule', () {
    var s = RegionsState.initial(puzzle);
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (!puzzle.isGiven(i)) s = s.select(i).setValue(puzzle.solution[i]);
    }
    expect(s.isFull, isTrue);
    expect(s.isSolved, isTrue);
    final wrong = s.select(7).setValue(3);
    expect(wrong.isFull, isTrue);
    expect(wrong.isSolved, isFalse);
    expect(wrong.conflicts(), {6, 7});
  });

  test('share lines are spoiler-free squares per row', () {
    var s = RegionsState.initial(puzzle).select(0).setValue(1).select(1).reveal();
    expect(s.shareLines(), ['🟩🟨⬛⬛', '⬛⬛⬜⬜']);
    s = s.select(6).setValue(3).select(7).setValue(4);
    expect(s.shareLines(), ['🟩🟨⬛⬛', '⬛⬛🟩🟩']);
  });

  test('progress round trips through json', () {
    final s = RegionsState.initial(puzzle)
        .select(0)
        .toggleNotesMode()
        .input(1)
        .input(3)
        .toggleNotesMode()
        .select(6)
        .setValue(4)
        .select(7)
        .reveal()
        .check()
        .tick(42)
        .select(1);
    final json = s.toJson();
    expect(json['values'], '..123444');
    expect(json['flagged'], [6]);
    expect(json['revealed'], [7]);
    final back = RegionsState.fromJson(puzzle, json);
    expect(back.values, s.values);
    expect(back.notesAt(0), {1, 3});
    expect(back.flagged, {6});
    expect(back.revealed, {7});
    expect(back.hints, 2);
    expect(back.elapsedSeconds, 42);
    expect(back.selected, 1);
    expect(back.notesMode, isFalse);
    expect(back.undoStack.length, 4);
    expect(back.toJson(), json);
    expect(back.undo().undo().undo().undo().values, puzzle.givens);
  });

  test('fromJson rejects malformed or foreign progress', () {
    final good = RegionsState.initial(puzzle).select(0).setValue(1).toJson();
    expect(() => RegionsState.fromJson(puzzle, {}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'values': '1.2234..'}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'values': '1.1234.'}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'notes': [0, 0]}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'undo': 'x'}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'undo': [[9, 0, 0, 1, 0]]}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'flagged': [8]}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'hints': -1}), throwsFormatException);
    expect(() => RegionsState.fromJson(puzzle, {...good, 'selected': 8}), throwsFormatException);
    final minimal = RegionsState.fromJson(puzzle, {'values': '1.1234..', 'notes': List.filled(8, 0)});
    expect(minimal.values[0], 1);
    expect(minimal.hints, 0);
    expect(minimal.flagged, isEmpty);
  });
}
