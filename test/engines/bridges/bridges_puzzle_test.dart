import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Matcher rejects(String phrase) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(phrase)));

void main() {
  test('parses a valid payload and reveal', () {
    final puzzle = ringPuzzle();
    expect(puzzle.layout.width, 3);
    expect(puzzle.layout.height, 3);
    expect(puzzle.islandCount, 4);
    expect(puzzle.layout.pairs.length, 4);
    expect(puzzle.solution, ringSolution);
    expect(puzzle.bridgeCount, 4);
    expect(puzzle.toPayload(), ringPayload);
    expect(puzzle.toReveal(), ringReveal);
  });

  test('pairs join only islands that face each other with nothing between', () {
    final layout = BridgesLayout.parse(crossingPayload);
    expect(layout.pairs.length, 6);
    expect(layout.pairBetween(0, 1), 0);
    expect(layout.pairBetween(1, 0), 0);
    expect(layout.pairBetween(0, 3), isNull, reason: 'not aligned');
    expect(layout.pairBetween(1, 5), isNull, reason: 'not aligned');
    final vertical = layout.pairs[crossingVerticalPair];
    final horizontal = layout.pairs[crossingHorizontalPair];
    expect(vertical.horizontal, isFalse);
    expect(horizontal.horizontal, isTrue);
    expect(vertical.crossings, [crossingHorizontalPair]);
    expect(horizontal.crossings, [crossingVerticalPair]);
    expect(layout.islandAt(2, 4), 3);
    expect(layout.islandAt(1, 1), -1);
    expect(layout.islandAt(-1, 0), -1);
    final blocked = BridgesLayout.parse(chainPayload);
    expect(blocked.pairBetween(0, 2), isNull, reason: 'an island sits between');
  });

  test('rejects missing or malformed fields', () {
    expect(() => BridgesPuzzle.parse({}, ringReveal), rejects('width'));
    expect(() => BridgesPuzzle.parse({'width': 3, 'height': 3}, ringReveal), rejects('islands'));
    expect(() => BridgesPuzzle.parse({'width': '3', 'height': 3, 'islands': []}, ringReveal), rejects('width'));
    expect(() => BridgesPuzzle.parse(withIslands(ringPayload, [island(0, 0, 2), {'row': 0, 'col': 2}]), ringReveal), rejects('island 1'));
    expect(() => BridgesPuzzle.parse(ringPayload, {}), rejects('bridges'));
    expect(() => BridgesPuzzle.parse(ringPayload, {'bridges': [1]}), rejects('bridge 0'));
    expect(() => BridgesPuzzle.parse(ringPayload, {'bridges': [{'from': 0, 'to': 1}]}), rejects('bridge 0'));
  });

  test('rejects boards and islands out of range', () {
    expect(() => BridgesLayout.parse({...ringPayload, 'width': 1}), rejects('board'));
    expect(() => BridgesLayout.parse({...ringPayload, 'height': 31}), rejects('board'));
    expect(() => BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 1)])), rejects('two islands'));
    expect(() => BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 1), island(0, 3, 1)])), rejects('off the board'));
    expect(() => BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 1), island(-1, 2, 1)])), rejects('off the board'));
    expect(() => BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 0), island(0, 2, 1)])), rejects('count'));
    expect(() => BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 9), island(0, 2, 1)])), rejects('count'));
    expect(() => BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 1), island(0, 0, 1)])), rejects('share a cell'));
  });

  test('rejects reveal bridges that break the geometry', () {
    Map<String, dynamic> reveal(Map<String, dynamic> extra) => {'bridges': [...ringReveal['bridges'] as List, extra]};
    expect(() => BridgesPuzzle.parse(ringPayload, reveal(bridge(0, 4, 1))), rejects('do not exist'));
    expect(() => BridgesPuzzle.parse(ringPayload, reveal(bridge(2, 2, 1))), rejects('do not exist'));
    expect(() => BridgesPuzzle.parse(ringPayload, reveal(bridge(0, 3, 1))), rejects('not in line'));
    expect(() => BridgesPuzzle.parse(ringPayload, reveal(bridge(0, 1, 1))), rejects('twice'));
    expect(() => BridgesPuzzle.parse(ringPayload, {'bridges': [bridge(0, 1, 3)]}), rejects('1 or 2'));
    expect(() => BridgesPuzzle.parse(ringPayload, {'bridges': [bridge(0, 1, 0)]}), rejects('1 or 2'));
  });

  test('rejects a crossing bridge', () {
    expect(() => BridgesPuzzle.parse(crossedPayload, crossedReveal), rejects('cross'));
    final layout = BridgesLayout.parse(crossedPayload);
    final board = [1, 1, 1, 1];
    expect(layout.crossingPairs(board), {2, 3});
    expect(layout.firstFault(board), BridgesFault.crossing);
  });

  test('rejects a reveal that misses or exceeds a count', () {
    expect(() => BridgesPuzzle.parse(ringPayload, {'bridges': [bridge(0, 1, 1), bridge(0, 2, 1), bridge(1, 3, 1)]}), rejects('too few'));
    expect(() => BridgesPuzzle.parse(ringPayload, {'bridges': [bridge(0, 1, 2), bridge(0, 2, 1), bridge(1, 3, 1), bridge(2, 3, 1)]}), rejects('too many'));
  });

  test('rejects a disconnected reveal even when every count is met', () {
    final twoComponents = {'bridges': [bridge(0, 1, 2), bridge(2, 3, 2)]};
    expect(() => BridgesPuzzle.parse(ringPayload, twoComponents), rejects('joined'));
    final layout = BridgesLayout.parse(ringPayload);
    expect(layout.isConnected([2, 0, 0, 2]), isFalse);
    expect(layout.isConnected(ringSolution), isTrue);
    expect(layout.firstFault([2, 0, 0, 2]), BridgesFault.disconnected);
  });

  test('rejects a puzzle with more than one solution', () {
    expect(() => BridgesPuzzle.parse(twoSolutionsPayload, twoSolutionsReveal), rejects('unique'));
  });

  test('accepts a valid solved board', () {
    final layout = BridgesLayout.parse(ringPayload);
    expect(layout.firstFault(ringSolution), isNull);
    expect(layout.isSolution(ringSolution), isTrue);
    expect(layout.isSolution([1, 1, 1, 0]), isFalse);
    expect(layout.isSolution([3, 0, 0, 1]), isFalse);
    expect(() => layout.firstFault([1, 1, 1]), throwsArgumentError);
  });

  test('the constructor checks a raw solution', () {
    final layout = BridgesLayout.parse(ringPayload);
    expect(() => BridgesPuzzle(layout: layout, solution: [1, 1, 1]), rejects('pairs'));
    expect(() => BridgesPuzzle(layout: layout, solution: [1, 1, 1, 2]), rejects('too many'));
    expect(BridgesPuzzle(layout: layout, solution: ringSolution).solution, ringSolution);
  });

  test('reveal order does not matter and from/to may be swapped', () {
    final swapped = {'bridges': [bridge(3, 2, 1), bridge(3, 1, 1), bridge(2, 0, 1), bridge(1, 0, 1)]};
    final puzzle = BridgesPuzzle.parse(ringPayload, swapped);
    expect(puzzle.solution, ringSolution);
    expect(puzzle.toReveal(), ringReveal);
  });
}
