
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';
import 'package:playthepaper/features/games/tangram/tangram_board.dart';

void main() {
  test('the piece drawn on top is the one the hit test picks', () {
    const square = TangramPlacement(piece: TangramPiece.square, x: 4, y: 4);
    const large = TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 4);
    final placed = {TangramPiece.largeTriangleA: large, TangramPiece.square: square};

    // Find a point inside both polygons.
    Offset? overlap;
    for (var y = 1.0; y < 8 && overlap == null; y += 0.25) {
      for (var x = 1.0; x < 8; x += 0.25) {
        if (TangramGeometry.contains(square.polygon(), x, y) && TangramGeometry.contains(large.polygon(), x, y)) {
          overlap = Offset(x, y);
          break;
        }
      }
    }
    expect(overlap, isNotNull, reason: 'the two pieces must overlap for this test');

    // Nothing selected: the later piece in the fixed order (square) is on top.
    expect(TangramBoard.stackingOrder(placed, null).last, TangramPiece.square);
    expect(TangramBoard.pieceAt(placed, overlap!), TangramPiece.square);

    // Selecting the triangle draws it on top, so it must be the one picked.
    expect(TangramBoard.stackingOrder(placed, TangramPiece.largeTriangleA).last, TangramPiece.largeTriangleA);
    expect(TangramBoard.pieceAt(placed, overlap, selected: TangramPiece.largeTriangleA), TangramPiece.largeTriangleA);

    // And the reverse.
    expect(TangramBoard.pieceAt(placed, overlap, selected: TangramPiece.square), TangramPiece.square);
  });
}
