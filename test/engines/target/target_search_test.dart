import 'package:playthepaper/engines/target/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tiles = [100, 75, 3, 6, 7, 9];

  test('finds a solution whose expression the evaluator accepts', () {
    final search = TargetSearch(tiles);
    final solution = search.solve(952)!;
    expect(TargetExpression.evaluate(solution.expression.text, tiles), 952);
    expect(solution.tilesUsed, solution.expression.numbers.length);
    expect(search.isReachable(952), isTrue);
    expect(search.minTiles(103), 2);
    expect(search.solve(103)!.expression.text, '100 + 3');
  });

  test('every reachable target has a valid expression and the shortest one', () {
    final search = TargetSearch(tiles);
    for (var target = 101; target <= 999; target++) {
      final solution = search.solve(target);
      if (solution == null) continue;
      expect(TargetExpression.evaluate(solution.expression.text, tiles), target, reason: '$target');
      expect(solution.tilesUsed, inInclusiveRange(1, 6));
    }
  });

  test('rejects a target that cannot be made', () {
    final search = TargetSearch(tiles);
    expect(search.isReachable(983), isFalse);
    expect(search.solve(998), isNull);
    expect(search.minTiles(998), isNull);
    expect(TargetSearch([1, 2]).isReachable(4), isFalse);
    expect(TargetSearch([25, 50, 1, 1, 2, 2]).isReachable(109), isFalse);
  });

  test('never goes negative, never divides inexactly', () {
    expect(TargetSearch([3, 7]).isReachable(4), isTrue, reason: '7 - 3');
    expect(TargetSearch([2, 7]).isReachable(3), isFalse, reason: '7 / 2 is not exact');
    expect(TargetSearch([2, 7]).isReachable(1), isFalse, reason: 'neither 2 - 7 nor 7 - 2 makes 1 without a fraction');
    expect(TargetSearch([1, 8]).isReachable(7), isTrue);
    expect(TargetSearch([3, 3]).isReachable(0), isFalse, reason: 'zero is not allowed');
  });

  test('never uses a tile twice', () {
    expect(TargetSearch([1, 3]).isReachable(9), isFalse);
    expect(TargetSearch([3, 3]).isReachable(9), isTrue);
    expect(TargetSearch([1, 3]).isReachable(6), isFalse);
  });

  test('closest reports the nearest reachable value', () {
    expect(TargetSearch([25, 50, 1, 1, 2, 2]).closest(109), (108, 1));
    expect(TargetSearch(tiles).closest(952), (952, 0));
    expect(TargetSearch([1, 2]).closest(4), (3, 1));
  });
}
