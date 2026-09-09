import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/chronology/chronology.dart';

import 'fixtures.dart';

void main() {
  final puzzle = ChronologyPuzzle.parse(flightPayload(), flightReveal());

  test('starts in the payload order with nothing in place', () {
    final state = ChronologyState.initial(puzzle);
    expect(state.order, ['b', 'd', 'a', 'c']);
    expect(state.points, 0);
    expect(state.isSolved, isFalse);
    expect(state.canUndo, isFalse);
    expect(state.canHint, isTrue);
    expect(state.submitted, isFalse);
  });

  test('moves shift the cards between the two positions and can be undone', () {
    var state = ChronologyState.initial(puzzle).move(2, 0);
    expect(state.order, ['a', 'b', 'd', 'c']);
    expect(state.points, 2);
    state = state.moveDown(2);
    expect(state.order, ['a', 'b', 'c', 'd']);
    expect(state.points, 4);
    expect(state.isSolved, isFalse, reason: 'not submitted yet');
    state = state.undo();
    expect(state.order, ['a', 'b', 'd', 'c']);
    state = state.undo();
    expect(state.order, ['b', 'd', 'a', 'c']);
    expect(state.canUndo, isFalse);
    expect(identical(state.undo(), state), isTrue);
  });

  test('ignores moves that are out of range, to the same place, or after submitting', () {
    final state = ChronologyState.initial(puzzle);
    expect(identical(state.move(0, 0), state), isTrue);
    expect(identical(state.move(-1, 2), state), isTrue);
    expect(identical(state.move(0, 4), state), isTrue);
    expect(identical(state.moveUp(0), state), isTrue);
    expect(identical(state.moveDown(3), state), isTrue);
    final submitted = state.submit();
    expect(identical(submitted.move(0, 1), submitted), isTrue);
    expect(identical(submitted.submit(), submitted), isTrue);
    expect(submitted.canUndo, isFalse);
    expect(submitted.canHint, isFalse);
  });

  test('scores one point per card in place once submitted', () {
    final state = ChronologyState.initial(puzzle).move(2, 0).submit();
    expect(state.order, ['a', 'b', 'd', 'c']);
    expect(state.points, 2);
    expect(state.isCorrectAt(0), isTrue);
    expect(state.isCorrectAt(2), isFalse);
    expect(state.isSolved, isFalse);
    expect(state.shareLines(), ['🕰 2/4', '🟩🟩🟥🟥']);
    final solved = ChronologyState.initial(puzzle).move(2, 0).moveDown(2).submit();
    expect(solved.isSolved, isTrue);
    expect(solved.shareLines(), ['🕰 4/4', '🟩🟩🟩🟩']);
  });

  test('a hint places the earliest misplaced card, locks the top and cannot be undone', () {
    var state = ChronologyState.initial(puzzle).move(1, 0);
    expect(state.order, ['d', 'b', 'a', 'c']);
    state = state.hint();
    expect(state.order, ['a', 'd', 'b', 'c']);
    expect(state.lockedCount, 1);
    expect(state.hints, 1);
    expect(state.canUndo, isFalse);
    expect(identical(state.moveUp(1), state), isTrue, reason: 'cannot move into the locked prefix');
    expect(identical(state.move(1, 0), state), isTrue);
    expect(state.move(2, 1).order, ['a', 'b', 'd', 'c']);
    state = state.move(2, 1).hint();
    expect(state.order, ['a', 'b', 'c', 'd'], reason: 'b was already in place, so c is placed');
    expect(state.lockedCount, 3);
    expect(state.hints, 2);
    expect(state.canHint, isFalse);
    expect(identical(state.hint(), state), isTrue);
    expect(state.points, 4);
    expect(state.isSolved, isFalse);
    expect(state.submit().isSolved, isTrue);
  });

  test('a hint on an already correct order locks everything', () {
    final state = ChronologyState.initial(puzzle).move(2, 0).moveDown(2).hint();
    expect(state.lockedCount, 4);
    expect(state.hints, 1);
    expect(state.canHint, isFalse);
  });

  test('progress round-trips through json', () {
    final state = ChronologyState.initial(puzzle).move(2, 0).move(3, 1).hint();
    final json = state.toJson();
    expect(json['order'], ['a', 'b', 'c', 'd']);
    final restored = ChronologyState.fromJson(puzzle, json);
    expect(restored, state);
    expect(restored.lockedCount, 2);
    expect(restored.hints, 1);
    final submitted = ChronologyState.fromJson(puzzle, state.submit().toJson());
    expect(submitted.submitted, isTrue);
    final withUndo = ChronologyState.initial(puzzle).move(0, 3).move(1, 2);
    expect(ChronologyState.fromJson(puzzle, withUndo.toJson()).undo().undo(), ChronologyState.initial(puzzle));
  });

  test('rejects progress that does not belong to the puzzle', () {
    void rejects(Map<String, dynamic> json) => expect(() => ChronologyState.fromJson(puzzle, json), throwsFormatException);
    rejects({'order': ['a', 'b', 'c']});
    rejects({'order': ['a', 'b', 'c', 'e']});
    rejects({'order': ['a', 'a', 'b', 'c']});
    rejects({'order': 'abcd'});
    rejects({'order': ['a', 'b', 'c', 'd'], 'undo': 'x'});
    rejects({'order': ['a', 'b', 'c', 'd'], 'undo': [['a', 'b']]});
    rejects({'order': ['b', 'a', 'c', 'd'], 'locked': 1});
    rejects({'order': ['a', 'b', 'c', 'd'], 'locked': 5});
    rejects({'order': ['a', 'b', 'c', 'd'], 'hints': -1});
    expect(ChronologyState.fromJson(puzzle, {'order': ['a', 'b', 'c', 'd'], 'locked': 2}).lockedCount, 2);
  });
}
