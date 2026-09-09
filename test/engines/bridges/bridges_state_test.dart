import 'dart:convert';

import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final ring = ringPuzzle();

  test('the initial state has no bridges, no selection and nothing to undo', () {
    final s = BridgesState.initial(ring);
    expect(s.board, [0, 0, 0, 0]);
    expect(s.selected, isNull);
    expect(s.canUndo, isFalse);
    expect(s.hints, 0);
    expect(s.elapsedSeconds, 0);
    expect(s.isSolved, isFalse);
    expect(s.fault, BridgesFault.underCount);
    expect(s.completeIslands, 0);
    expect(s.reachable, isEmpty);
    for (var i = 0; i < 4; i++) {
      expect(s.status(i), BridgesIslandStatus.under);
    }
  });

  test('taps select, connect, double, remove and reselect', () {
    var s = BridgesState.initial(ring).tap(0);
    expect(s.selected, 0);
    expect(s.reachable, {1, 2});
    s = s.tap(1);
    expect(s.board, [1, 0, 0, 0]);
    expect(s.selected, 0, reason: 'the selection stays for a repeat tap');
    s = s.tap(1);
    expect(s.board, [2, 0, 0, 0]);
    expect(s.status(0), BridgesIslandStatus.complete);
    expect(s.status(1), BridgesIslandStatus.complete);
    s = s.tap(2);
    expect(s.board, [2, 1, 0, 0]);
    expect(s.status(0), BridgesIslandStatus.over);
    expect(s.load(0), 3);
    s = s.tap(1);
    expect(s.board, [0, 1, 0, 0], reason: 'a third tap on a double removes it');
    s = s.tap(3);
    expect(s.selected, 3, reason: 'an island out of line becomes the selection');
    expect(s.board, [0, 1, 0, 0]);
    s = s.tap(3);
    expect(s.selected, isNull, reason: 'tapping the selected island clears it');
    expect(s.canUndo, isTrue);
    expect(s.undoStack.length, 4);
    expect(() => s.select(4), throwsRangeError);
    expect(() => s.setBridges(0, 3), throwsRangeError);
    expect(identical(s.setBridges(1, 1), s), isTrue, reason: 'no change is no move');
  });

  test('a crossing bridge is refused', () {
    final puzzle = crossingPuzzle();
    var s = BridgesState.initial(puzzle).setBridges(crossingVerticalPair, 1);
    expect(s.board[crossingVerticalPair], 1);
    expect(s.wouldCross(crossingHorizontalPair), isTrue);
    expect(identical(s.setBridges(crossingHorizontalPair, 1), s), isTrue);
    expect(s.select(2).tap(3).board, s.board, reason: 'a tap cannot draw the crossing bridge either');
    s = s.setBridges(crossingVerticalPair, 0);
    expect(s.wouldCross(crossingHorizontalPair), isFalse);
    expect(s.setBridges(crossingHorizontalPair, 1).board[crossingHorizontalPair], 1);
  });

  test('a disconnected network with every count met is not solved', () {
    final s = BridgesState.initial(ring).setBridges(0, 2).setBridges(3, 2);
    expect(s.completeIslands, 4);
    expect(s.isSolved, isFalse);
    expect(s.fault, BridgesFault.disconnected);
  });

  test('a valid solved board is accepted', () {
    var s = BridgesState.initial(ring);
    for (var p = 0; p < 4; p++) {
      s = s.setBridges(p, 1);
    }
    expect(s.isSolved, isTrue);
    expect(s.fault, isNull);
    expect(s.board, ringSolution);
    expect(identical(s.hint(), s), isTrue);
  });

  test('undo steps back through moves and hints but keeps the hint count', () {
    var s = BridgesState.initial(ring).setBridges(0, 1).setBridges(1, 2).hint();
    expect(s.hints, 1);
    expect(s.undoStack.length, 3);
    s = s.undo();
    expect(s.board, [1, 2, 0, 0]);
    expect(s.hints, 1);
    s = s.undo();
    expect(s.board, [1, 0, 0, 0]);
    s = s.undo();
    expect(s.board, [0, 0, 0, 0]);
    expect(s.canUndo, isFalse);
    expect(identical(s.undo(), s), isTrue);
  });

  test('a hint removes a wrong bridge first, then draws a certain one', () {
    var s = BridgesState.initial(ring).setBridges(0, 2);
    s = s.hint();
    expect(s.board, [1, 0, 0, 0], reason: 'the double on the top edge is wrong');
    expect(s.hints, 1);
    s = s.hint();
    expect(s.hints, 2);
    expect(s.board.fold(0, (a, b) => a + b), 2);
    expect(s.board.every((b) => b <= 1), isTrue);
    while (!s.isSolved) {
      s = s.hint();
    }
    expect(s.board, ringSolution);
    expect(s.hints, 4);
  });

  test('a hint falls back to the solution when propagation stalls', () {
    final hard = BridgesPuzzle.parse(hardPayload, hardReveal);
    var s = BridgesState.initial(hard);
    while (!s.isSolved) {
      final before = s.board.fold(0, (a, b) => a + b);
      s = s.hint();
      expect(s.board.fold(0, (a, b) => a + b), before + 1);
    }
    expect(s.board, hard.solution);
    expect(s.hints, hard.bridgeCount);
  });

  test('progress survives a json round trip', () {
    final s = BridgesState.initial(ring).tap(0).tap(1).tap(1).tap(2).hint().tick(75);
    final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
    final back = BridgesState.fromJson(ring, json);
    expect(back.board, s.board);
    expect(back.undoStack.length, s.undoStack.length);
    expect(back.undoStack.last.toJson(), s.undoStack.last.toJson());
    expect(back.hints, 1);
    expect(back.elapsedSeconds, 75);
    expect(back.selected, 0);
    expect(back.undo().board, s.undo().board);
  });

  test('malformed progress is rejected', () {
    expect(() => BridgesState.fromJson(ring, {}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [1, 1, 1]}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [1, 1, 1, 3]}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [1, 1, 1, 'x']}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [0, 0, 0, 0], 'undo': 3}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [0, 0, 0, 0], 'undo': [[9, 0, 1]]}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [0, 0, 0, 0], 'hints': -1}), throwsFormatException);
    expect(() => BridgesState.fromJson(ring, {'bridges': [0, 0, 0, 0], 'selected': 4}), throwsFormatException);
    final crossed = crossingPuzzle();
    expect(() => BridgesState.fromJson(crossed, {'bridges': [0, 0, 1, 1, 0, 0]}), throwsFormatException);
    final minimal = BridgesState.fromJson(ring, {'bridges': [0, 1, 0, 0]});
    expect(minimal.board, [0, 1, 0, 0]);
    expect(minimal.hints, 0);
    expect(minimal.canUndo, isFalse);
  });
}
