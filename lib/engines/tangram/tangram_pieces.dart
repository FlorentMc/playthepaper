import 'tangram_geometry.dart';

/// The seven pieces of the standard dissection, on a lattice where the
/// assembled square is four units on a side.
///
/// Each piece is drawn around its own turning point, which sits on the
/// lattice near the middle of the piece, so a quarter turn about it keeps
/// every corner on the lattice. In those units the small triangles have legs
/// of √2 and a hypotenuse of 2, the square has a side of √2, the medium
/// triangle has legs of 2, the large triangles have legs of 2√2 and a
/// hypotenuse of 4, and the parallelogram has sides of √2 and 2. The seven
/// areas are 4, 4, 2, 1, 1, 2 and 2: sixteen units together, the area of the
/// square they make.
enum TangramPiece {
  largeTriangleA('largeTriangleA', 'Large triangle', _largeTriangle, 4),
  largeTriangleB('largeTriangleB', 'Large triangle', _largeTriangle, 4),
  mediumTriangle('mediumTriangle', 'Medium triangle', _mediumTriangle, 2),
  smallTriangleA('smallTriangleA', 'Small triangle', _smallTriangle, 1),
  smallTriangleB('smallTriangleB', 'Small triangle', _smallTriangle, 1),
  square('square', 'Square', _square, 2),
  parallelogram('parallelogram', 'Parallelogram', _parallelogram, 2);

  const TangramPiece(this.slug, this.label, this.shape, this.area);

  final String slug;

  /// What the piece is called in the help and in semantics.
  final String label;

  /// Corners around the turning point, clockwise as drawn.
  final List<TangramPoint> shape;
  final double area;

  /// Only the parallelogram has a mirror image that is not one of its own
  /// turns, so only the parallelogram may be turned over.
  bool get canFlip => this == parallelogram;

  static TangramPiece fromSlug(String slug) {
    for (final piece in values) {
      if (piece.slug == slug) return piece;
    }
    throw FormatException('Unknown tangram piece: $slug');
  }
}

const List<TangramPoint> _largeTriangle = [
  TangramPoint(0, -1),
  TangramPoint(2, 1),
  TangramPoint(-2, 1),
];
const List<TangramPoint> _mediumTriangle = [
  TangramPoint(-1, -1),
  TangramPoint(1, 1),
  TangramPoint(-1, 1),
];
const List<TangramPoint> _smallTriangle = [
  TangramPoint(0, -1),
  TangramPoint(1, 0),
  TangramPoint(-1, 0),
];
const List<TangramPoint> _square = [
  TangramPoint(0, -1),
  TangramPoint(1, 0),
  TangramPoint(0, 1),
  TangramPoint(-1, 0),
];
const List<TangramPoint> _parallelogram = [
  TangramPoint(0, -1),
  TangramPoint(2, -1),
  TangramPoint(1, 0),
  TangramPoint(-1, 0),
];

/// One piece on the board: where its turning point sits, how far it is turned
/// and whether it has been turned over.
class TangramPlacement {
  const TangramPlacement({
    required this.piece,
    required this.x,
    required this.y,
    this.rotation = 0,
    this.flipped = false,
  });

  final TangramPiece piece;

  /// The turning point, in board units.
  final int x;
  final int y;

  /// Eighths of a turn clockwise, 0 to 7.
  final int rotation;
  final bool flipped;

  static const int turns = 8;
  static const double _diagonal = 0.7071067811865476;
  static const List<double> _cos = [1, _diagonal, 0, -_diagonal, -1, -_diagonal, 0, _diagonal];
  static const List<double> _sin = [0, _diagonal, 1, _diagonal, 0, -_diagonal, -1, -_diagonal];

  int get degrees => rotation * 45;

  /// The corners of the piece on the board, clockwise as drawn. At a quarter
  /// turn every corner lands exactly on the lattice.
  List<TangramPoint> polygon() {
    final cos = _cos[rotation], sin = _sin[rotation];
    final corners = <TangramPoint>[];
    for (final corner in piece.shape) {
      final lx = flipped ? -corner.x : corner.x;
      corners.add(TangramPoint(x + lx * cos - corner.y * sin, y + lx * sin + corner.y * cos));
    }
    if (flipped) return corners.reversed.toList(growable: false);
    return corners;
  }

  bool get isOnLattice => polygon().every((p) => p.isLattice);

  /// True when every corner sits inside the board.
  bool get isOnBoard => polygon().every((p) =>
      p.x >= 0 && p.y >= 0 && p.x <= TangramGeometry.boardUnits && p.y <= TangramGeometry.boardUnits);

  TangramPlacement movedTo(int nx, int ny) =>
      TangramPlacement(piece: piece, x: nx, y: ny, rotation: rotation, flipped: flipped);

  TangramPlacement turned(int steps) => TangramPlacement(
        piece: piece,
        x: x,
        y: y,
        rotation: ((rotation + steps) % turns + turns) % turns,
        flipped: flipped,
      );

  TangramPlacement flip() =>
      TangramPlacement(piece: piece, x: x, y: y, rotation: rotation, flipped: !flipped);

  Map<String, dynamic> toJson() => {
        'piece': piece.slug,
        'x': x,
        'y': y,
        'rotation': degrees,
        'flipped': flipped,
      };

  static TangramPlacement fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Tangram placement must be an object');
    final json = Map<String, dynamic>.from(raw);
    final slug = json['piece'];
    if (slug is! String) throw const FormatException('Tangram placement is missing "piece"');
    final piece = TangramPiece.fromSlug(slug);
    final x = json['x'], y = json['y'], degrees = json['rotation'] ?? 0;
    if (x is! int || y is! int) {
      throw FormatException('Tangram placement of $slug needs whole "x" and "y" board units');
    }
    if (degrees is! int || degrees % 45 != 0 || degrees < 0 || degrees >= 360) {
      throw FormatException('Tangram rotation of $slug must be 0, 45, 90 … 315, got $degrees');
    }
    final flipped = json['flipped'] ?? false;
    if (flipped is! bool) throw FormatException('Tangram "flipped" of $slug must be true or false');
    if (flipped && !piece.canFlip) {
      throw FormatException('Only the parallelogram may be turned over, not $slug');
    }
    return TangramPlacement(piece: piece, x: x, y: y, rotation: degrees ~/ 45, flipped: flipped);
  }

  @override
  bool operator ==(Object other) =>
      other is TangramPlacement &&
      other.piece == piece &&
      other.x == x &&
      other.y == y &&
      other.rotation == rotation &&
      other.flipped == flipped;

  @override
  int get hashCode => Object.hash(piece, x, y, rotation, flipped);

  @override
  String toString() => '${piece.slug}@($x,$y) $degrees°${flipped ? ' flipped' : ''}';
}
