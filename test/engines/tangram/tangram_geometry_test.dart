import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';

import 'fixtures.dart';

void main() {
  group('pieces', () {
    test('the seven areas add up to the square they came from', () {
      var total = 0.0;
      for (final piece in TangramPiece.values) {
        final area = TangramGeometry.signedArea(piece.shape).abs();
        expect(area, piece.area, reason: piece.slug);
        total += area;
      }
      expect(total, TangramGeometry.pieceArea);
    });

    test('every piece is drawn the same way round', () {
      for (final piece in TangramPiece.values) {
        expect(TangramGeometry.signedArea(piece.shape), greaterThan(0), reason: piece.slug);
      }
    });

    test('a quarter turn keeps every corner on the lattice and a half of one does not', () {
      for (final piece in TangramPiece.values) {
        for (var rotation = 0; rotation < 8; rotation++) {
          final placement = TangramPlacement(piece: piece, x: 4, y: 4, rotation: rotation);
          expect(placement.isOnLattice, rotation.isEven, reason: '${piece.slug} at ${rotation * 45}°');
        }
      }
    });

    test('turning keeps the area and comes back round after eight steps', () {
      for (final piece in TangramPiece.values) {
        var placement = TangramPlacement(piece: piece, x: 4, y: 4);
        for (var step = 0; step < 8; step++) {
          expect(TangramGeometry.signedArea(placement.polygon()), closeTo(piece.area, 1e-9));
          placement = placement.turned(1);
        }
        expect(placement.rotation, 0);
      }
    });

    test('only the parallelogram changes shape when it is turned over', () {
      for (final piece in TangramPiece.values) {
        final upright = TangramPlacement(piece: piece, x: 4, y: 4).polygon().toSet();
        final over = TangramPlacement(piece: piece, x: 4, y: 4, flipped: true).polygon().toSet();
        final turns = [
          for (var r = 0; r < 8; r += 2)
            TangramPlacement(piece: piece, x: 4, y: 4, rotation: r).polygon().toSet()
        ];
        expect(turns.any((t) => _same(t, over)), piece != TangramPiece.parallelogram,
            reason: piece.slug);
        expect(_same(upright, over), piece != TangramPiece.parallelogram && piece != TangramPiece.mediumTriangle,
            reason: piece.slug);
      }
    });

    test('a piece is on the board only while every corner is', () {
      expect(const TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 1).isOnBoard, isTrue);
      expect(const TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 0).isOnBoard, isFalse);
      expect(const TangramPlacement(piece: TangramPiece.square, x: 0, y: 4).isOnBoard, isFalse);
    });
  });

  group('outline', () {
    test('the seven pieces in their square give one square contour', () {
      final loops = TangramGeometry.unionOutline(squareSolution.map((p) => p.polygon()));
      expect(loops, hasLength(1));
      expect(loops.first, hasLength(4));
      expect(TangramGeometry.signedArea(loops.first), TangramGeometry.pieceArea);
      expect(loops.first.toSet(), {
        const TangramPoint(0, 0),
        const TangramPoint(4, 0),
        const TangramPoint(4, 4),
        const TangramPoint(0, 4),
      });
    });

    test('two pieces that only touch at a point give two contours', () {
      final loops = TangramGeometry.unionOutline([
        const TangramPlacement(piece: TangramPiece.square, x: 2, y: 2).polygon(),
        const TangramPlacement(piece: TangramPiece.square, x: 4, y: 4).polygon(),
      ]);
      expect(loops, hasLength(2));
    });

    test('a piece off the lattice cannot be outlined', () {
      expect(
        () => TangramGeometry.unionOutline([
          const TangramPlacement(piece: TangramPiece.square, x: 4, y: 4, rotation: 1).polygon(),
        ]),
        throwsFormatException,
      );
    });
  });

  group('raster', () {
    test('the square covers sixteen units of samples', () {
      final mask = TangramGeometry.rasteriseUnion(squareSolution.map((p) => p.polygon()));
      expect(mask.size, TangramGeometry.maskSize);
      expect(mask.filled, 16 * TangramGeometry.resolution * TangramGeometry.resolution);
    });

    test('the outline and the pieces rasterise to the same shape', () {
      final polygons = squareSolution.map((p) => p.polygon()).toList();
      final fromPieces = TangramGeometry.rasteriseUnion(polygons);
      final fromOutline = TangramGeometry.rasteriseOutline(TangramGeometry.unionOutline(polygons));
      expect(fromOutline.difference(fromPieces), 0);
    });

    test('no sample ever sits on a piece edge', () {
      for (var row = 0; row < TangramGeometry.maskSize; row++) {
        for (var col = 0; col < TangramGeometry.maskSize; col++) {
          final p = TangramGeometry.sampleAt(col, row);
          expect(p.x % 1, isNot(0));
          expect(p.y % 1, isNot(0));
          expect((p.x + p.y) % 1, isNot(0));
          expect((p.x - p.y) % 1, isNot(0));
        }
      }
    });

    test('a mask rejects rows of the wrong width or with strange characters', () {
      expect(() => TangramMask.fromRows(['11', '1']), throwsFormatException);
      expect(() => TangramMask.fromRows(['1x', '11']), throwsFormatException);
      expect(TangramMask.fromRows(['00', '00']).filled, 0);
    });
  });

  group('overlap', () {
    test('a piece laid on itself overlaps by its whole area', () {
      final square = const TangramPlacement(piece: TangramPiece.square, x: 4, y: 4).polygon();
      expect(TangramGeometry.overlapArea(square, square), closeTo(2, 1e-9));
    });

    test('pieces that share only an edge do not overlap', () {
      for (var i = 0; i < squareSolution.length; i++) {
        for (var j = i + 1; j < squareSolution.length; j++) {
          expect(
            TangramGeometry.overlapArea(squareSolution[i].polygon(), squareSolution[j].polygon()),
            lessThan(1e-9),
            reason: '${squareSolution[i].piece.slug} and ${squareSolution[j].piece.slug}',
          );
        }
      }
    });

    test('a piece nudged one unit onto its neighbour overlaps', () {
      final a = const TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 3).polygon();
      final b = const TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 2).polygon();
      expect(TangramGeometry.overlapArea(a, b), greaterThan(0.5));
    });
  });
}

bool _same(Set<TangramPoint> a, Set<TangramPoint> b) => a.length == b.length && a.containsAll(b);
