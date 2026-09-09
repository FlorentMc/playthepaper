import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('counts exactly one solution for a unique puzzle and finds it', () {
    for (final (payload, reveal) in [(ringPayload, ringReveal), (chainPayload, chainReveal), (crossingPayload, crossingReveal), (hardPayload, hardReveal)]) {
      final layout = BridgesLayout.parse(payload);
      expect(BridgesSolver.countSolutions(layout), 1);
      expect(BridgesSolver.countSolutions(layout, limit: 5), 1);
      expect(BridgesSolver.solve(layout), BridgesPuzzle.parse(payload, reveal).solution);
    }
  });

  test('counts two solutions for the ambiguous square', () {
    final layout = BridgesLayout.parse(twoSolutionsPayload);
    expect(BridgesSolver.countSolutions(layout), 2);
    expect(BridgesSolver.countSolutions(layout, limit: 1), 1);
    expect(BridgesSolver.countSolutions(layout, limit: 0), 0);
    final found = BridgesSolver.solve(layout)!;
    expect(layout.isSolution(found), isTrue);
  });

  test('a board whose only pairs cross has no solution', () {
    final layout = BridgesLayout.parse(plusPayload);
    expect(layout.pairs.length, 2);
    expect(layout.pairs[0].crossings, [1]);
    expect(BridgesSolver.countSolutions(layout), 0);
    expect(BridgesSolver.solve(layout), isNull);
  });

  test('a network that satisfies every count but falls into two parts is not a solution', () {
    final layout = BridgesLayout.parse(ringPayload);
    expect(layout.firstFault([2, 0, 0, 2]), BridgesFault.disconnected);
    final ones = BridgesLayout.parse(withIslands(ringPayload, [island(0, 0, 1), island(0, 2, 1), island(2, 0, 1), island(2, 2, 1)]));
    expect(ones.firstFault([1, 0, 0, 1]), BridgesFault.disconnected);
    expect(ones.firstFault([0, 1, 1, 0]), BridgesFault.disconnected);
    expect(BridgesSolver.countSolutions(ones), 0, reason: 'every count-satisfying board is two separate pairs');
  });

  test('propagation settles the ring through the connection argument', () {
    final layout = BridgesLayout.parse(ringPayload);
    final counting = BridgesSolver.propagate(layout, connection: false)!;
    expect(counting.isDecided, isFalse);
    expect(counting.min, [0, 0, 0, 0]);
    expect(counting.max, [2, 2, 2, 2]);
    final full = BridgesSolver.propagate(layout)!;
    expect(full.isDecided, isTrue);
    expect(full.min, ringSolution);
  });

  test('propagation from drawn bridges keeps them and reports a contradiction', () {
    final layout = BridgesLayout.parse(crossingPayload);
    final bounds = BridgesSolver.propagate(layout, lower: [0, 0, 0, 1, 0, 0])!;
    expect(bounds.min[crossingHorizontalPair], 1);
    expect(bounds.max[crossingVerticalPair], 0);
    expect(bounds.isDecided, isTrue);
    expect(BridgesSolver.propagate(layout, lower: [0, 0, 1, 0, 0, 0]), isNull, reason: 'the vertical bridge leaves C unreachable');
    expect(() => BridgesSolver.propagate(layout, lower: [0, 0, 3, 0, 0, 0]), throwsArgumentError);
  });

  test('rates puzzles by the reasoning they need', () {
    expect(BridgesSolver.rate(BridgesLayout.parse(chainPayload)), BridgesRating.easy);
    expect(BridgesSolver.rate(BridgesLayout.parse(ringPayload)), BridgesRating.medium);
    expect(BridgesSolver.rate(BridgesLayout.parse(hardPayload)), BridgesRating.hard);
  });
}
