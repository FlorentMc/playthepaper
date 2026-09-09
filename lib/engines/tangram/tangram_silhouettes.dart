import 'tangram_geometry.dart';
import 'tangram_pieces.dart';
import 'tangram_puzzle.dart';

/// One authored figure: a name and the seven pieces that make it.
class TangramSilhouette {
  const TangramSilhouette({required this.name, required this.placements});

  final String name;
  final List<TangramPlacement> placements;

  /// The same figure shifted so it sits in the middle of the board.
  TangramSilhouette centred() {
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final placement in placements) {
      for (final corner in placement.polygon()) {
        left = corner.x < left ? corner.x : left;
        right = corner.x > right ? corner.x : right;
        top = corner.y < top ? corner.y : top;
        bottom = corner.y > bottom ? corner.y : bottom;
      }
    }
    const board = TangramGeometry.boardUnits;
    final dx = ((board - (right - left)) / 2 - left).round();
    final dy = ((board - (bottom - top)) / 2 - top).round();
    if (dx == 0 && dy == 0) return this;
    return TangramSilhouette(
      name: name,
      placements: [for (final p in placements) p.movedTo(p.x + dx, p.y + dy)],
    );
  }

  TangramPuzzle toPuzzle() => TangramPuzzle.fromSolution(name: name, placements: placements);

  static TangramSilhouette fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('A silhouette is missing "name"');
    }
    final raw = json['placements'];
    if (raw is! List || raw.length != TangramPiece.values.length) {
      throw FormatException('"$name" needs ${TangramPiece.values.length} placements');
    }
    return TangramSilhouette(
      name: name,
      placements: List.unmodifiable(raw.map(TangramPlacement.fromJson)),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'placements': [for (final placement in placements) placement.toJson()],
      };
}

/// The authored figures, an exact copy of `content_src/tangram/silhouettes.json`
/// so the generator needs no file access. A test keeps the two in step.
const List<TangramSilhouette> tangramSilhouettes = [
  TangramSilhouette(
    name: "Sailboat",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 2, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 4, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Yacht",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 4, y: 7),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 4, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Leaf",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 5, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 4, y: 6),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 5),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 4, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Tower",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 7),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 4, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Kite",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 5, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Hourglass",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 5),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 6, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 6),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 5),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 4, y: 4, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Fox",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 5),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 2, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 3, y: 1, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 1, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 3, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Swan",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 5, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 1, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 6),
      TangramPlacement(piece: TangramPiece.square, x: 6, y: 5),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 3, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Cat",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 6, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 5),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 4, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Lamp",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 6, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 7),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 4, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Torch",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 7),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 6, y: 6, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 6, rotation: 4, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Lantern",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 2, rotation: 4, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Signpost",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 5),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 4, rotation: 6),
    ],
  ),
  TangramSilhouette(
    name: "Anchor",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 6, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 1, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 6, y: 1, rotation: 6, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Comet",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 1),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 6, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 6, y: 4, rotation: 4),
    ],
  ),
  TangramSilhouette(
    name: "Basket",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 4, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Spinning top",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 1, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 2, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 5, rotation: 4),
    ],
  ),
  TangramSilhouette(
    name: "Bench",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 1, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 1, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 6, y: 4, rotation: 6, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Bow tie",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 5, y: 5),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 6, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 6, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 5),
      TangramPlacement(piece: TangramPiece.square, x: 2, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 6, rotation: 6),
    ],
  ),
  TangramSilhouette(
    name: "Pine tree",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 5),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 3, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 6, y: 2, rotation: 6, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Mushroom",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 3, rotation: 6, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Bridge",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 5, y: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 1, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 4, rotation: 6),
    ],
  ),
  TangramSilhouette(
    name: "Balloon",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 3),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 6, y: 3),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 6, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 4, y: 7, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Crown",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 6, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 2, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 2, y: 3),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 2, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Ox",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 2, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 1, y: 3),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 4, y: 5),
      TangramPlacement(piece: TangramPiece.square, x: 7, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 6, y: 5, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Key",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 6, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 7, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 3, rotation: 6),
    ],
  ),
  TangramSilhouette(
    name: "Barge",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 6, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 1, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 2, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 5, rotation: 4),
    ],
  ),
  TangramSilhouette(
    name: "Acorn",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 5, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 3, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 6, y: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 3, rotation: 4, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Seal",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 6, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 2, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 4, y: 4),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 4, y: 7),
    ],
  ),
  TangramSilhouette(
    name: "Chimney",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 5, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Arrowhead",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 2, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 3),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 2, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 2, rotation: 4, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Whale",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 1, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 6, y: 3),
    ],
  ),
  TangramSilhouette(
    name: "Bell",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 6, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 4, y: 2),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 6, rotation: 4, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Postbox",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 5, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 3, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 6, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 3, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 3, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Duck",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 2, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 5, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 1, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 7, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 7, y: 5, rotation: 6),
    ],
  ),
  TangramSilhouette(
    name: "Boot",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 5, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 6, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 3, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 6, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Hammer",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 7, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 6, rotation: 2, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Rocket",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 1, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 1, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 5, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.square, x: 2, y: 1),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 2),
    ],
  ),
  TangramSilhouette(
    name: "Bird",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 6, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 3),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 3, rotation: 4),
    ],
  ),
  TangramSilhouette(
    name: "Castle",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 5, y: 2, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 4, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 4, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 4, y: 3, rotation: 4),
    ],
  ),
  TangramSilhouette(
    name: "Lighthouse",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 4, y: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 6, rotation: 4),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 4, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 4, rotation: 4),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 3, y: 2, rotation: 6, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Rabbit",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 5, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 3, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 5, y: 5, rotation: 6),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 5, y: 2, rotation: 2),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 5, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 6, y: 3),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 5, y: 7, flipped: true),
    ],
  ),
  TangramSilhouette(
    name: "Hat",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 6, y: 3, rotation: 6),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 5, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 6, y: 5),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 3, y: 4, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 2),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 3, rotation: 2),
    ],
  ),
  TangramSilhouette(
    name: "Aeroplane",
    placements: [
      TangramPlacement(piece: TangramPiece.largeTriangleA, x: 3, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.largeTriangleB, x: 4, y: 3),
      TangramPlacement(piece: TangramPiece.mediumTriangle, x: 5, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleA, x: 2, y: 3, rotation: 4),
      TangramPlacement(piece: TangramPiece.smallTriangleB, x: 6, y: 3, rotation: 2),
      TangramPlacement(piece: TangramPiece.square, x: 5, y: 5, rotation: 4),
      TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 3),
    ],
  ),
];
