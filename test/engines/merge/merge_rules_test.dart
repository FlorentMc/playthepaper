import 'package:playthepaper/engines/merge/merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slideLine', () {
    void expectLine(List<int> line, List<int> tiles, int gained, {List<int>? merged}) {
      final result = MergeRules.slideLine(line);
      expect(result.tiles, tiles, reason: '$line');
      expect(result.gained, gained, reason: '$line');
      if (merged != null) expect(result.merged, merged, reason: '$line');
    }

    test('tiles slide over gaps without merging', () {
      expectLine([0, 0, 0, 2], [2, 0, 0, 0], 0, merged: []);
      expectLine([0, 2, 0, 4], [2, 4, 0, 0], 0);
      expectLine([2, 4, 8, 16], [2, 4, 8, 16], 0);
    });

    test('two equal tiles merge into their sum and score it', () {
      expectLine([2, 2, 0, 0], [4, 0, 0, 0], 4, merged: [0]);
      expectLine([0, 2, 0, 2], [4, 0, 0, 0], 4);
      expectLine([8, 8, 8, 8], [16, 16, 0, 0], 32, merged: [0, 1]);
    });

    test('a row of four equal tiles makes two pairs, not one big tile', () {
      expectLine([2, 2, 2, 2], [4, 4, 0, 0], 8, merged: [0, 1]);
    });

    test('2 2 4 makes 4 4, never 8', () {
      expectLine([2, 2, 4, 0], [4, 4, 0, 0], 4, merged: [0]);
    });

    test('a tile that has just merged does not merge again on the same slide', () {
      expectLine([4, 4, 8, 0], [8, 8, 0, 0], 8, merged: [0]);
      expectLine([2, 2, 4, 4], [4, 8, 0, 0], 12, merged: [0, 1]);
    });

    test('merging happens from the front of the line', () {
      expectLine([4, 2, 2, 0], [4, 4, 0, 0], 4, merged: [1]);
      expectLine([2, 2, 2, 0], [4, 2, 0, 0], 4, merged: [0]);
    });
  });

  group('slide', () {
    final board = [
      2, 0, 0, 2, //
      4, 4, 0, 0, //
      0, 0, 8, 0, //
      2, 0, 0, 0, //
    ];

    test('left packs every row towards column one', () {
      final slide = MergeRules.slide(board, 4, MergeDirection.left);
      expect(slide.tiles, [
        4, 0, 0, 0, //
        8, 0, 0, 0, //
        8, 0, 0, 0, //
        2, 0, 0, 0, //
      ]);
      expect(slide.gained, 12);
      expect(slide.merged, {0, 4});
      expect(slide.changed, isTrue);
    });

    test('right packs every row towards the last column', () {
      final slide = MergeRules.slide(board, 4, MergeDirection.right);
      expect(slide.tiles, [
        0, 0, 0, 4, //
        0, 0, 0, 8, //
        0, 0, 0, 8, //
        0, 0, 0, 2, //
      ]);
      expect(slide.merged, {3, 7});
    });

    test('up packs every column towards the first row', () {
      final slide = MergeRules.slide(board, 4, MergeDirection.up);
      expect(slide.tiles, [
        2, 4, 8, 2, //
        4, 0, 0, 0, //
        2, 0, 0, 0, //
        0, 0, 0, 0, //
      ]);
      expect(slide.gained, 0);
    });

    test('down packs every column towards the last row', () {
      final slide = MergeRules.slide(board, 4, MergeDirection.down);
      expect(slide.tiles, [
        0, 0, 0, 0, //
        2, 0, 0, 0, //
        4, 0, 0, 0, //
        2, 4, 8, 2, //
      ]);
    });

    test('a slide that moves nothing reports no change and no score', () {
      final packed = [
        2, 4, 0, 0, //
        8, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ];
      final slide = MergeRules.slide(packed, 4, MergeDirection.left);
      expect(slide.changed, isFalse);
      expect(slide.gained, 0);
      expect(slide.tiles, packed);
    });

    test('a board of the wrong length is rejected', () {
      expect(() => MergeRules.slide([1, 2, 3], 4, MergeDirection.left), throwsFormatException);
    });
  });

  group('hasMove', () {
    test('an empty square always leaves a move', () {
      expect(MergeRules.hasMove(List<int>.filled(16, 0), 4), isTrue);
    });

    test('a full board with equal neighbours still has a move', () {
      final tiles = [
        2, 4, 2, 4, //
        4, 2, 4, 2, //
        2, 4, 2, 4, //
        4, 2, 4, 4, //
      ];
      expect(MergeRules.hasMove(tiles, 4), isTrue);
    });

    test('a full board with no equal neighbours is stuck', () {
      final tiles = [
        2, 4, 2, 4, //
        4, 2, 4, 2, //
        2, 4, 2, 4, //
        4, 2, 4, 2, //
      ];
      expect(MergeRules.hasMove(tiles, 4), isFalse);
      for (final d in MergeDirection.values) {
        expect(MergeRules.slide(tiles, 4, d).changed, isFalse, reason: d.slug);
      }
    });

    test('it agrees with trying all four slides', () {
      final random = MergeRandom(2026);
      for (var trial = 0; trial < 200; trial++) {
        final tiles = List<int>.generate(16, (_) {
          final r = random.nextInt(6);
          return r == 0 ? 0 : 1 << r;
        });
        final any = MergeDirection.values.any((d) => MergeRules.slide(tiles, 4, d).changed);
        expect(MergeRules.hasMove(tiles, 4), any, reason: '$tiles');
      }
    });
  });

  group('spawn', () {
    test('a new tile lands on an empty square and is a 2 or a 4', () {
      final random = MergeRandom(7);
      final tiles = List<int>.filled(16, 0);
      tiles[5] = 8;
      for (var i = 0; i < 15; i++) {
        final at = MergeRules.spawn(tiles, random);
        expect(at, isNot(5));
        expect(tiles[at] == 2 || tiles[at] == 4, isTrue);
      }
      expect(MergeRules.emptyCells(tiles), isEmpty);
      expect(MergeRules.spawn(tiles, random), -1);
    });

    test('about one tile in ten is a 4', () {
      final random = MergeRandom(11);
      var fours = 0;
      for (var i = 0; i < 4000; i++) {
        final tiles = List<int>.filled(16, 0);
        final at = MergeRules.spawn(tiles, random);
        if (tiles[at] == 4) fours++;
      }
      expect(fours, inInclusiveRange(300, 500));
    });

    test('the opening deals two tiles', () {
      final tiles = MergeRules.opening(MergeRandom(4242), 4);
      expect(tiles.where((v) => v != 0).length, 2);
    });
  });

  group('helpers', () {
    test('the size is bounded', () {
      expect(() => MergeRules.checkSize(2), throwsFormatException);
      expect(() => MergeRules.checkSize(9), throwsFormatException);
      MergeRules.checkSize(4);
    });

    test('only powers of two are tiles', () {
      expect(MergeRules.isTile(2), isTrue);
      expect(MergeRules.isTile(2048), isTrue);
      expect(MergeRules.isTile(0), isFalse);
      expect(MergeRules.isTile(1), isFalse);
      expect(MergeRules.isTile(6), isFalse);
      expect(MergeRules.isTile(-4), isFalse);
    });

    test('rank counts the doublings', () {
      expect(MergeRules.rankOf(2), 1);
      expect(MergeRules.rankOf(1024), 10);
      expect(MergeRules.rankOf(2048), 11);
    });

    test('scores are grouped in threes', () {
      expect(MergeRules.groupDigits(0), '0');
      expect(MergeRules.groupDigits(999), '999');
      expect(MergeRules.groupDigits(5432), '5,432');
      expect(MergeRules.groupDigits(1234567), '1,234,567');
    });

    test('directions round trip through their slugs', () {
      for (final d in MergeDirection.values) {
        expect(MergeDirection.fromSlug(d.slug), d);
      }
      expect(() => MergeDirection.fromSlug('sideways'), throwsFormatException);
    });
  });

  group('MergeRandom', () {
    test('the same state always gives the same numbers', () {
      final a = MergeRandom(12345);
      final b = MergeRandom(12345);
      for (var i = 0; i < 50; i++) {
        expect(a.next(), b.next());
      }
    });

    test('a resumed generator carries on where it stopped', () {
      final a = MergeRandom(999);
      for (var i = 0; i < 10; i++) {
        a.next();
      }
      final resumed = MergeRandom(a.state);
      final b = MergeRandom(999);
      for (var i = 0; i < 10; i++) {
        b.next();
      }
      for (var i = 0; i < 20; i++) {
        expect(resumed.next(), b.next());
      }
    });

    test('numbers stay inside 32 bits and inside the bound', () {
      final random = MergeRandom(3);
      for (var i = 0; i < 1000; i++) {
        expect(random.next(), inInclusiveRange(0, 0xFFFFFFFF));
        expect(random.nextInt(16), inInclusiveRange(0, 15));
      }
      expect(() => random.nextInt(0), throwsRangeError);
    });

    test('a zero seed is folded away from the fixed point', () {
      expect(MergeRandom.normalise(0), isNot(0));
      expect(MergeRandom(0).next(), isNot(0));
    });
  });
}
