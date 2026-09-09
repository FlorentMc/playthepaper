import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';

import 'fixtures.dart';

void main() {
  final puzzle = squarePuzzle();
  final payload = puzzle.toPayload();
  final reveal = puzzle.toReveal();

  Map<String, dynamic> withPayload(String key, Object? value) => {...payload, key: value};

  group('placements', () {
    test('round trip through json', () {
      for (final placement in squareSolution) {
        expect(TangramPlacement.fromJson(placement.toJson()), placement);
      }
    });

    test('rotation is written in degrees', () {
      expect(
        const TangramPlacement(piece: TangramPiece.square, x: 1, y: 2, rotation: 3).toJson(),
        {'piece': 'square', 'x': 1, 'y': 2, 'rotation': 135, 'flipped': false},
      );
    });

    test('rejects an unknown piece', () {
      expect(() => TangramPlacement.fromJson({'piece': 'trapezium', 'x': 1, 'y': 1}), throwsFormatException);
    });

    test('rejects a rotation that is not a multiple of 45 degrees', () {
      expect(() => TangramPlacement.fromJson({'piece': 'square', 'x': 1, 'y': 1, 'rotation': 30}),
          throwsFormatException);
      expect(() => TangramPlacement.fromJson({'piece': 'square', 'x': 1, 'y': 1, 'rotation': 360}),
          throwsFormatException);
    });

    test('rejects fractional board units', () {
      expect(() => TangramPlacement.fromJson({'piece': 'square', 'x': 1.5, 'y': 1}), throwsFormatException);
    });

    test('rejects turning over anything but the parallelogram', () {
      expect(() => TangramPlacement.fromJson({'piece': 'square', 'x': 1, 'y': 1, 'flipped': true}),
          throwsFormatException);
      expect(TangramPlacement.fromJson({'piece': 'parallelogram', 'x': 1, 'y': 1, 'flipped': true}).flipped,
          isTrue);
    });
  });

  group('parse', () {
    test('accepts a puzzle it wrote itself', () {
      final parsed = TangramPuzzle.parse(payload, reveal);
      expect(parsed.name, 'Square');
      expect(parsed.mask.filled, puzzle.mask.filled);
      expect(parsed.solution, squareSolution);
      expect(parsed.outline.first, hasLength(4));
      expect(parsed.bounds, (left: 0.0, top: 0.0, right: 4.0, bottom: 4.0));
    });

    test('rejects a missing name', () {
      expect(() => TangramPuzzle.parse(withPayload('name', ''), reveal), throwsFormatException);
    });

    test('rejects a board of the wrong size', () {
      expect(() => TangramPuzzle.parse(withPayload('board', 10), reveal), throwsFormatException);
    });

    test('rejects a mask of the wrong shape', () {
      expect(() => TangramPuzzle.parse(withPayload('mask', ['11', '11']), reveal), throwsFormatException);
      expect(() => TangramPuzzle.parse(withPayload('mask', null), reveal), throwsFormatException);
    });

    test('rejects an outline that is not the shape of the mask', () {
      final moved = [
        for (final loop in puzzle.outline)
          [for (final corner in loop) [(corner.x + 1) / 8, corner.y / 8]]
      ];
      expect(() => TangramPuzzle.parse(withPayload('silhouette', moved), reveal), throwsFormatException);
    });

    test('rejects an outline corner off the lattice or off the board', () {
      expect(
        () => TangramPuzzle.parse(withPayload('silhouette', [
              [
                [0.1, 0.2],
                [0.3, 0.2],
                [0.3, 0.4]
              ]
            ]), reveal),
        throwsFormatException,
      );
      expect(
        () => TangramPuzzle.parse(withPayload('silhouette', [
              [
                [1.25, 0.25],
                [0.5, 0.25],
                [0.5, 0.5]
              ]
            ]), reveal),
        throwsFormatException,
      );
    });

    test('rejects a reveal with a piece missing or placed twice', () {
      final short = squareSolution.sublist(0, 6).map((p) => p.toJson()).toList();
      expect(() => TangramPuzzle.parse(payload, {'placements': short}), throwsFormatException);
      final twice = [...short, short.first];
      expect(() => TangramPuzzle.parse(payload, {'placements': twice}), throwsFormatException);
    });

    test('rejects a reveal whose pieces overlap', () {
      final overlapping = [
        for (final placement in squareSolution)
          placement.piece == TangramPiece.square ? placement.movedTo(2, 3) : placement,
      ];
      expect(
        () => TangramPuzzle.parse(payload, {'placements': overlapping.map((p) => p.toJson()).toList()}),
        throwsFormatException,
      );
    });

    test('rejects a reveal that does not make the figure', () {
      final shifted = [
        for (final placement in squareSolution)
          placement.piece == TangramPiece.square ? placement.movedTo(6, 6) : placement,
      ];
      expect(
        () => TangramPuzzle.parse(payload, {'placements': shifted.map((p) => p.toJson()).toList()}),
        throwsFormatException,
      );
    });

    test('rejects a piece off the board or off the lattice', () {
      final off = [
        for (final placement in squareSolution)
          placement.piece == TangramPiece.square ? placement.movedTo(0, 0) : placement,
      ];
      expect(() => TangramPuzzle.parse(payload, {'placements': off.map((p) => p.toJson()).toList()}),
          throwsFormatException);
      final tilted = [
        for (final placement in squareSolution)
          placement.piece == TangramPiece.square ? placement.turned(1) : placement,
      ];
      expect(() => TangramPuzzle.parse(payload, {'placements': tilted.map((p) => p.toJson()).toList()}),
          throwsFormatException);
    });

    test('rejects a reveal with no placements at all', () {
      expect(() => TangramPuzzle.parse(payload, const {}), throwsFormatException);
    });

    test('fromSolution rejects an arrangement whose pieces overlap', () {
      expect(
        () => TangramPuzzle.fromSolution(name: 'Bad', placements: [
          for (final placement in squareSolution)
            placement.piece == TangramPiece.square ? placement.movedTo(2, 3) : placement,
        ]),
        throwsFormatException,
      );
    });
  });
}
