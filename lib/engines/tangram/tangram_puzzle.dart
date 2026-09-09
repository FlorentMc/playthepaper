import 'tangram_checker.dart';
import 'tangram_geometry.dart';
import 'tangram_pieces.dart';

/// A validated silhouette and the arrangement that makes it.
///
/// Payload:
/// ```json
/// {"name": "Swan", "board": 8,
///  "silhouette": [[[0.25, 0.5], ...]],
///  "mask": ["0011…", … 32 rows of 32]}
/// ```
/// `silhouette` holds one closed loop per contour, in fractions of the board,
/// as `docs/ARCHITECTURE.md` describes; `mask` is the same shape rasterised
/// four samples to the unit, which is what completion is measured against.
///
/// Reveal:
/// ```json
/// {"placements": [{"piece": "largeTriangleA", "x": 2, "y": 3, "rotation": 90, "flipped": false}, ×7]}
/// ```
/// Placement `x` and `y` are whole board units, 0 to 8.
class TangramPuzzle {
  const TangramPuzzle._({
    required this.name,
    required this.mask,
    required this.outline,
    required this.solution,
  });

  /// The figure's name, shown once the shape is made.
  final String name;
  final TangramMask mask;

  /// The silhouette's contours, in board units.
  final List<List<TangramPoint>> outline;

  /// One arrangement that makes the shape. Others may too.
  final List<TangramPlacement> solution;

  /// Builds a puzzle from an arrangement, deriving the outline and the mask.
  factory TangramPuzzle.fromSolution({required String name, required List<TangramPlacement> placements}) {
    _checkPlacements(name, placements);
    final polygons = placements.map((p) => p.polygon()).toList(growable: false);
    final outline = TangramGeometry.unionOutline(polygons);
    return _build(
      name: name,
      outline: outline,
      mask: TangramGeometry.rasteriseUnion(polygons),
      placements: placements,
    );
  }

  static TangramPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final name = payload['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Tangram payload is missing "name"');
    }
    final board = payload['board'];
    if (board != TangramGeometry.boardUnits) {
      throw FormatException('Tangram board must be ${TangramGeometry.boardUnits} units, got $board');
    }
    final rawOutline = payload['silhouette'];
    if (rawOutline is! List || rawOutline.isEmpty) {
      throw const FormatException('Tangram payload is missing "silhouette"');
    }
    final outline = rawOutline.map(_parseLoop).toList(growable: false);
    final mask = TangramMask.parse(payload['mask'], size: TangramGeometry.maskSize);
    final rawPlacements = reveal['placements'];
    if (rawPlacements is! List) {
      throw const FormatException('Tangram reveal is missing "placements"');
    }
    final placements = rawPlacements.map(TangramPlacement.fromJson).toList(growable: false);
    _checkPlacements(name, placements);
    return _build(name: name, outline: outline, mask: mask, placements: placements);
  }

  /// Validates the whole record: the pieces must not overlap, they must cover
  /// the mask, and the drawn outline must be the same shape as the mask.
  static TangramPuzzle _build({
    required String name,
    required List<List<TangramPoint>> outline,
    required TangramMask mask,
    required List<TangramPlacement> placements,
  }) {
    if (mask.filled == 0) throw FormatException('The mask of "$name" is blank');
    var area = 0.0;
    for (final loop in outline) {
      if (loop.length < 3) throw FormatException('A contour of "$name" has fewer than three corners');
      area += TangramGeometry.signedArea(loop);
    }
    if ((area - TangramGeometry.pieceArea).abs() > 1e-6) {
      throw FormatException(
          'The silhouette of "$name" covers $area units, not ${TangramGeometry.pieceArea}');
    }
    if (TangramGeometry.rasteriseOutline(outline).difference(mask) != 0) {
      throw FormatException('The outline and the mask of "$name" are different shapes');
    }
    final check = TangramChecker.check(mask, placements);
    if (!check.isComplete) {
      throw FormatException(
          'The given arrangement does not make "$name": ${check.missed} samples short, '
          '${check.spilled} over, overlap ${(check.overlap * 100).toStringAsFixed(1)}%');
    }
    return TangramPuzzle._(
      name: name,
      mask: mask,
      outline: List.unmodifiable(outline.map(List<TangramPoint>.unmodifiable)),
      solution: List.unmodifiable(placements),
    );
  }

  static void _checkPlacements(String name, List<TangramPlacement> placements) {
    final seen = <TangramPiece>{};
    for (final placement in placements) {
      if (!seen.add(placement.piece)) {
        throw FormatException('"$name" places ${placement.piece.slug} twice');
      }
      if (!placement.isOnLattice) {
        throw FormatException('"$name" places ${placement.piece.slug} off the lattice at $placement');
      }
      if (!placement.isOnBoard) {
        throw FormatException('"$name" places ${placement.piece.slug} off the board at $placement');
      }
    }
    if (seen.length != TangramPiece.values.length) {
      final missing = TangramPiece.values.where((p) => !seen.contains(p)).map((p) => p.slug);
      throw FormatException('"$name" is missing ${missing.join(', ')}');
    }
    for (var i = 0; i < placements.length; i++) {
      for (var j = i + 1; j < placements.length; j++) {
        final shared = TangramGeometry.overlapArea(placements[i].polygon(), placements[j].polygon());
        if (shared > 1e-6) {
          throw FormatException(
              '"$name" overlaps ${placements[i].piece.slug} and ${placements[j].piece.slug}');
        }
      }
    }
  }

  static List<TangramPoint> _parseLoop(Object? raw) {
    if (raw is! List || raw.length < 3) {
      throw const FormatException('A tangram contour needs at least three corners');
    }
    return raw.map((point) {
      if (point is! List || point.length != 2 || point.any((v) => v is! num)) {
        throw const FormatException('A tangram corner must be a pair of numbers');
      }
      final x = (point[0] as num).toDouble() * TangramGeometry.boardUnits;
      final y = (point[1] as num).toDouble() * TangramGeometry.boardUnits;
      final corner = TangramPoint(x, y);
      if (!corner.isLattice) throw FormatException('Tangram corner $corner is off the lattice');
      if (x < 0 || y < 0 || x > TangramGeometry.boardUnits || y > TangramGeometry.boardUnits) {
        throw FormatException('Tangram corner $corner is off the board');
      }
      return corner;
    }).toList(growable: false);
  }

  TangramPlacement solutionFor(TangramPiece piece) => solution.firstWhere((p) => p.piece == piece);

  /// The tightest box around the silhouette, in board units.
  ({double left, double top, double right, double bottom}) get bounds {
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final loop in outline) {
      for (final point in loop) {
        left = point.x < left ? point.x : left;
        right = point.x > right ? point.x : right;
        top = point.y < top ? point.y : top;
        bottom = point.y > bottom ? point.y : bottom;
      }
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  Map<String, dynamic> toPayload() => {
        'name': name,
        'board': TangramGeometry.boardUnits,
        'silhouette': [
          for (final loop in outline)
            [
              for (final point in loop)
                [point.x / TangramGeometry.boardUnits, point.y / TangramGeometry.boardUnits],
            ],
        ],
        'mask': mask.toJson(),
      };

  Map<String, dynamic> toReveal() => {
        'placements': [for (final placement in solution) placement.toJson()],
      };
}
