import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/crossmatch/crossmatch.dart';

import 'fixtures.dart';

void main() {
  final puzzle = CrossmatchPuzzle.parse(placesPayload(), placesReveal());
  int tile(String name) => puzzle.tiles.indexOf(name);
  const cells = CrossmatchPuzzle.cellCount;

  CrossmatchState solvedState() {
    var state = CrossmatchState.initial(puzzle);
    for (var cell = 0; cell < cells; cell++) {
      state = state.place(puzzle.tileAt(cell), cell);
    }
    return state;
  }

  test('starts with every tile in the tray', () {
    final state = CrossmatchState.initial(puzzle);
    expect(state.tray.length, cells);
    expect(state.placement.every((t) => t == -1), isTrue);
    expect(state.isFull, isFalse);
    expect(state.points, 0);
    expect(state.canUndo, isFalse);
    expect(state.canCheck, isFalse, reason: 'nothing to check yet');
    expect(state.checksLeft, CrossmatchState.maxChecks);
  });

  test('placing a tile takes it out of the tray and can be undone', () {
    final naples = tile('Naples');
    final state = CrossmatchState.initial(puzzle).place(naples, 0);
    expect(state.tileAt(0), naples);
    expect(state.cellOf(naples), 0);
    expect(state.tray, isNot(contains(naples)));
    expect(state.tray.length, cells - 1);
    expect(state.canUndo, isTrue);
    expect(state.isCorrectAt(0), isTrue);
    expect(state.fitsAt(0), isTrue);
    expect(state.points, 1);
    expect(state.undo().tray.length, cells);
    expect(state.undo().canUndo, isFalse);
  });

  test('a cell holds one tile, and the tile it displaces goes back to the tray', () {
    final naples = tile('Naples');
    final hekla = tile('Hekla');
    final state = CrossmatchState.initial(puzzle).place(naples, 0).place(hekla, 0);
    expect(state.tileAt(0), hekla);
    expect(state.tray, contains(naples));
    expect(state.isCorrectAt(0), isFalse);
    expect(state.fitsAt(0), isFalse);
    expect(state.points, 0);
  });

  test('moving a placed tile empties the cell it came from', () {
    final naples = tile('Naples');
    final state = CrossmatchState.initial(puzzle).place(naples, 0).place(naples, 4);
    expect(state.tileAt(0), isNull);
    expect(state.tileAt(4), naples);
    expect(state.clear(4).tileAt(4), isNull);
    expect(state.clear(4).tray, contains(naples));
    expect(state.clear(0), same(state), reason: 'clearing an empty cell changes nothing');
    expect(state.place(naples, 4), same(state), reason: 'putting a tile where it already is changes nothing');
  });

  test('a check marks the misplaced tiles, counts against the total and clears on the next move', () {
    final naples = tile('Naples');
    var state = CrossmatchState.initial(puzzle).place(naples, 4);
    expect(state.canCheck, isTrue);
    state = state.check();
    expect(state.checks, 1);
    expect(state.checksLeft, CrossmatchState.maxChecks - 1);
    expect(state.wrong, [4]);
    expect(state.isMarked(4), isTrue);
    expect(state.isMarked(0), isFalse);
    expect(state.place(naples, 0).wrong, isNull, reason: 'a move clears the standing check');

    var right = CrossmatchState.initial(puzzle).place(naples, 0).check();
    expect(right.wrong, isEmpty, reason: 'checked and nothing is wrong');
    for (var i = 1; i < CrossmatchState.maxChecks; i++) {
      right = right.check();
    }
    expect(right.checks, CrossmatchState.maxChecks);
    expect(right.canCheck, isFalse);
    expect(right.check(), same(right));
  });

  test('a full and correct grid is solved once it is submitted', () {
    final state = solvedState();
    expect(state.isFull, isTrue);
    expect(state.points, cells);
    expect(state.rulesMet, isTrue);
    expect(state.isSolved, isFalse, reason: 'not submitted yet');
    final done = state.submit();
    expect(done.isSolved, isTrue);
    expect(done.shareLines(), ['🧩 9/9', '🟩🟩🟩', '🟩🟩🟩', '🟩🟩🟩']);
    expect(done.submit(), same(done));
    expect(done.place(tile('Hekla'), 0), same(done), reason: 'a submitted grid is read-only');
    expect(done.clear(0), same(done));
    expect(done.check(), same(done));
    expect(done.undo(), same(done));
  });

  test('a tile that fits a cell it does not belong in is still wrong', () {
    final surtsey = tile('Surtsey');
    final volcanoCell = CrossmatchPuzzle.cellIndex(2, 1);
    final state = CrossmatchState.initial(puzzle).place(surtsey, volcanoCell);
    expect(state.fitsAt(volcanoCell), isTrue, reason: 'Surtsey is a volcano in Iceland');
    expect(state.isCorrectAt(volcanoCell), isFalse, reason: 'but Hekla has nowhere else to go');
    expect(state.points, 0);
    expect(state.check().wrong, [volcanoCell]);
  });

  test('a part-finished grid scores the cells it got right', () {
    var state = CrossmatchState.initial(puzzle);
    state = state.place(puzzle.tileAt(0), 0).place(puzzle.tileAt(4), 4).place(puzzle.tileAt(1), 8);
    final done = state.submit();
    expect(done.points, 2);
    expect(done.isSolved, isFalse);
    expect(done.rulesMet, isFalse);
    expect(done.shareLines(), ['🧩 2/9', '🟩⬜⬜', '⬜🟩⬜', '⬜⬜🟥']);
  });

  test('progress round trips through json', () {
    final state = CrossmatchState.initial(puzzle).place(tile('Naples'), 0).place(tile('Hekla'), 4).check();
    final restored = CrossmatchState.fromJson(puzzle, state.toJson());
    expect(restored, state);
    expect(restored.wrong, [4]);
    expect(restored.undoStack.length, 2);
    expect(restored.checks, 1);

    final done = solvedState().submit();
    expect(CrossmatchState.fromJson(puzzle, done.toJson()).isSolved, isTrue);

    final fresh = CrossmatchState.initial(puzzle);
    expect(CrossmatchState.fromJson(puzzle, fresh.toJson()), fresh);
  });

  test('malformed progress is rejected', () {
    Map<String, dynamic> good() => CrossmatchState.initial(puzzle).place(tile('Naples'), 0).toJson();
    void rejects(Map<String, dynamic> json) => expect(() => CrossmatchState.fromJson(puzzle, json), throwsFormatException);

    rejects({});
    rejects(good()..['placement'] = [0, 1]);
    rejects(good()..['placement'] = [0, 0, -1, -1, -1, -1, -1, -1, -1]);
    rejects(good()..['placement'] = [9, -1, -1, -1, -1, -1, -1, -1, -1]);
    rejects(good()..['undo'] = 'nope');
    rejects(good()..['undo'] = [
          [0, 1],
        ]);
    rejects(good()..['checks'] = -1);
    rejects(good()..['checks'] = CrossmatchState.maxChecks + 1);
    rejects(good()..['wrong'] = [99]);
  });
}
