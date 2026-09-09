import 'dart:convert';

import 'package:playthepaper/engines/target/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final puzzle = TargetPuzzle.parse({'tiles': [25, 50, 7, 4, 3, 2], 'target': 353}, {'expression': '25 * 7 * (4 - 2) + 3'});

  test('initial state has the six given tiles', () {
    final s = TargetState.initial(puzzle);
    expect(s.tiles.map((t) => t.value), [25, 50, 7, 4, 3, 2]);
    expect(s.tiles.map((t) => t.id), [0, 1, 2, 3, 4, 5]);
    expect(s.tiles.every((t) => t.isGiven), isTrue);
    expect(s.steps, isEmpty);
    expect(s.canUndo, isFalse);
    expect(s.isSolved, isFalse);
    expect(s.isOver, isFalse);
    expect(s.closest, isNull);
    expect(s.note, 'Not solved');
    expect(s.target, 353);
  });

  test('a step consumes two tiles and makes a new one where the first stood', () {
    final s = TargetState.initial(puzzle).apply(0, TargetOp.multiply, 2);
    expect(s.steps.length, 1);
    expect(s.steps.single.display, '25 × 7 = 175');
    expect(s.tiles.map((t) => t.value), [175, 50, 4, 3, 2]);
    expect(s.tiles.first.id, 6);
    expect(s.tiles.first.step, 0);
    expect(s.tiles.first.isGiven, isFalse);
    expect(s.tile(0), isNull);
    expect(s.canUndo, isTrue);
    expect(s.closest, (175, 178));
    expect(s.note, 'Closest 175 (178 off)');
  });

  test('steps that break a rule are refused', () {
    final s = TargetState.initial(puzzle);
    expect(s.resultOf(5, TargetOp.subtract, 4), isNull, reason: '2 - 3');
    expect(s.resultOf(4, TargetOp.subtract, 4), isNull, reason: 'same tile');
    expect(s.resultOf(2, TargetOp.divide, 5), isNull, reason: '7 / 2');
    expect(s.resultOf(0, TargetOp.add, 9), isNull, reason: 'no such tile');
    expect(s.resultOf(1, TargetOp.divide, 0), 2);
    expect(identical(s.apply(5, TargetOp.subtract, 4), s), isTrue);
    expect(identical(s.apply(2, TargetOp.divide, 5), s), isTrue);
    expect(identical(s.apply(4, TargetOp.add, 4), s), isTrue);
    final used = s.apply(0, TargetOp.add, 1);
    expect(identical(used.apply(0, TargetOp.add, 2), used), isTrue, reason: 'a consumed tile cannot be used again');
  });

  test('undo and reset restore the table, and undo round-trips through json', () {
    var s = TargetState.initial(puzzle).apply(0, TargetOp.multiply, 2).apply(3, TargetOp.subtract, 5);
    expect(s.tiles.map((t) => t.value), [175, 50, 2, 3]);
    final json = jsonDecode(jsonEncode(s.tick(30).toJson())) as Map<String, dynamic>;
    final back = TargetState.fromJson(puzzle, json);
    expect(back.tiles.map((t) => t.value), [175, 50, 2, 3]);
    expect(back.elapsedSeconds, 30);
    expect(back.steps.map((x) => x.display), ['25 × 7 = 175', '4 − 2 = 2']);
    s = back.undo();
    expect(s.tiles.map((t) => t.value), [175, 50, 4, 3, 2]);
    expect(s.steps.length, 1);
    s = s.undo();
    expect(s.tiles.map((t) => t.value), [25, 50, 7, 4, 3, 2]);
    expect(identical(s.undo(), s), isTrue);
    final reset = back.reset();
    expect(reset.steps, isEmpty);
    expect(reset.elapsedSeconds, 30);
    expect(reset.tiles.map((t) => t.value), [25, 50, 7, 4, 3, 2]);
  });

  test('reaching the target solves the puzzle', () {
    var s = TargetState.initial(puzzle);
    s = s.apply(3, TargetOp.subtract, 5);
    s = s.apply(0, TargetOp.multiply, 2);
    s = s.apply(s.tiles.firstWhere((t) => t.value == 175).id, TargetOp.multiply, s.tiles.firstWhere((t) => t.value == 2).id);
    expect(s.isSolved, isFalse);
    s = s.apply(s.tiles.firstWhere((t) => t.value == 350).id, TargetOp.add, 4);
    expect(s.isSolved, isTrue);
    expect(s.isOver, isTrue);
    expect(s.note, 'Reached 353');
    expect(s.closest, (353, 0));
    expect(identical(s.apply(1, TargetOp.add, 1), s), isTrue);
  });

  test('giving up ends play', () {
    final s = TargetState.initial(puzzle).apply(0, TargetOp.add, 1).giveUp();
    expect(s.gaveUp, isTrue);
    expect(s.isOver, isTrue);
    expect(s.isSolved, isFalse);
    expect(s.note, 'Closest 75 (278 off)');
    expect(identical(s.apply(2, TargetOp.add, 3), s), isTrue);
    expect(identical(s.undo(), s), isTrue);
    expect(identical(s.giveUp(), s), isTrue);
    final back = TargetState.fromJson(puzzle, jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.gaveUp, isTrue);
    expect(back.steps.length, 1);
  });

  test('fromJson rejects malformed or impossible progress', () {
    expect(() => TargetState.fromJson(puzzle, {'steps': 'x'}), throwsFormatException);
    expect(() => TargetState.fromJson(puzzle, {'steps': [[0, '+']]}), throwsFormatException);
    expect(() => TargetState.fromJson(puzzle, {'steps': [[0, '%', 1]]}), throwsFormatException);
    expect(() => TargetState.fromJson(puzzle, {'steps': [[5, '-', 4]]}), throwsFormatException, reason: 'negative');
    expect(() => TargetState.fromJson(puzzle, {'steps': [[2, '/', 5]]}), throwsFormatException, reason: 'inexact');
    expect(() => TargetState.fromJson(puzzle, {'steps': [[0, '+', 1], [0, '+', 2]]}), throwsFormatException, reason: 'tile used twice');
    expect(() => TargetState.fromJson(puzzle, {'steps': [[0, '+', 9]]}), throwsFormatException, reason: 'no such tile');
    expect(() => TargetState.fromJson(puzzle, {'steps': [], 'elapsed': -1}), throwsFormatException);
    expect(() => TargetState.fromJson(puzzle, {'steps': [], 'gaveUp': 1}), throwsFormatException);
    expect(TargetState.fromJson(puzzle, {}).steps, isEmpty);
  });
}
