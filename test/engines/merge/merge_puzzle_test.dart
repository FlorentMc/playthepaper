import 'package:playthepaper/engines/merge/merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> payload({Object? seed = 12345, Object? size = 4}) => {
        'seed': ?seed,
        'size': ?size,
      };

  test('a good payload parses and deals the opening board', () {
    final puzzle = MergePuzzle.parse(payload(), const {});
    expect(puzzle.seed, 12345);
    expect(puzzle.size, 4);
    expect(puzzle.cellCount, 16);
    expect(puzzle.openingTiles.length, 16);
    expect(puzzle.openingTiles.where((v) => v != 0).length, 2);
    expect(puzzle.toPayload(), {'seed': 12345, 'size': 4});
    expect(puzzle.toReveal(), isEmpty);
  });

  test('the opening is the one the seed deals, every time', () {
    final a = MergePuzzle.parse(payload(), const {});
    final b = MergePuzzle.parse(payload(), const {});
    expect(a.openingTiles, b.openingTiles);
    expect(MergePuzzle(seed: 12346).openingTiles, isNot(a.openingTiles));
  });

  test('every seed opens with two 2s or 4s in different squares', () {
    for (var seed = 1; seed <= 400; seed++) {
      final tiles = MergePuzzle(seed: seed).openingTiles;
      final filled = [for (var i = 0; i < tiles.length; i++) if (tiles[i] != 0) i];
      expect(filled.length, 2, reason: 'seed $seed');
      expect(filled.first, isNot(filled.last), reason: 'seed $seed');
      for (final i in filled) {
        expect(tiles[i] == 2 || tiles[i] == 4, isTrue, reason: 'seed $seed');
      }
      expect(MergeRules.hasMove(tiles, 4), isTrue, reason: 'seed $seed');
    }
  });

  test('a missing or non-integer seed is rejected', () {
    expect(() => MergePuzzle.parse(payload(seed: null), const {}), throwsFormatException);
    expect(() => MergePuzzle.parse(payload(seed: '12345'), const {}), throwsFormatException);
    expect(() => MergePuzzle.parse(payload(seed: 1.5), const {}), throwsFormatException);
  });

  test('a seed outside 32 bits is rejected', () {
    expect(() => MergePuzzle.parse(payload(seed: 0), const {}), throwsFormatException);
    expect(() => MergePuzzle.parse(payload(seed: -1), const {}), throwsFormatException);
    expect(() => MergePuzzle.parse(payload(seed: 0x100000000), const {}), throwsFormatException);
    expect(MergePuzzle.parse(payload(seed: 0xFFFFFFFF), const {}).seed, 0xFFFFFFFF);
  });

  test('a missing or non-integer size is rejected', () {
    expect(() => MergePuzzle.parse(payload(size: null), const {}), throwsFormatException);
    expect(() => MergePuzzle.parse(payload(size: '4'), const {}), throwsFormatException);
  });

  test('a size outside the playable range is rejected', () {
    expect(() => MergePuzzle.parse(payload(size: 2), const {}), throwsFormatException);
    expect(() => MergePuzzle.parse(payload(size: 9), const {}), throwsFormatException);
    expect(MergePuzzle.parse(payload(size: 5), const {}).size, 5);
  });

  test('a reveal with anything in it is rejected', () {
    expect(() => MergePuzzle.parse(payload(), const {'solution': 'x'}), throwsFormatException);
  });
}
