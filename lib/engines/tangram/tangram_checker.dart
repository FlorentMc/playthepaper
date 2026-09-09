import 'tangram_geometry.dart';
import 'tangram_pieces.dart';

/// How close a set of placed pieces comes to filling a silhouette.
class TangramCheck {
  const TangramCheck({
    required this.placed,
    required this.missed,
    required this.spilled,
    required this.difference,
    required this.overlap,
  });

  /// Pieces on the board, out of seven.
  final int placed;

  /// Samples of the silhouette left uncovered.
  final int missed;

  /// Covered samples that fall outside the silhouette.
  final int spilled;

  /// Samples wrong either way, as a fraction of the silhouette.
  final double difference;

  /// Area covered by more than one piece, as a fraction of all seven.
  final double overlap;

  bool get isComplete =>
      placed == TangramPiece.values.length &&
      difference <= TangramChecker.maxDifference &&
      overlap <= TangramChecker.maxOverlap;
}

/// Checks a set of placements against a silhouette, without knowing how the
/// silhouette was made. Any arrangement that fills the shape counts, so a
/// figure with more than one answer is fair game.
class TangramChecker {
  const TangramChecker._();

  /// How much of the silhouette may be wrong, either uncovered or spilled
  /// over the edge.
  static const double maxDifference = 0.03;

  /// How much of the pieces' area may lie under another piece.
  static const double maxOverlap = 0.01;

  static TangramCheck check(TangramMask mask, Iterable<TangramPlacement> placements) {
    final placed = placements.toList(growable: false);
    final polygons = placed.map((p) => p.polygon()).toList(growable: false);
    final covered = TangramGeometry.rasteriseUnion(polygons);
    var missed = 0, spilled = 0;
    for (var row = 0; row < mask.size; row++) {
      for (var col = 0; col < mask.size; col++) {
        final wanted = mask.at(col, row);
        final has = covered.at(col, row);
        if (wanted && !has) missed++;
        if (!wanted && has) spilled++;
      }
    }
    var shared = 0.0;
    for (var i = 0; i < polygons.length; i++) {
      for (var j = i + 1; j < polygons.length; j++) {
        shared += TangramGeometry.overlapArea(polygons[i], polygons[j]);
      }
    }
    return TangramCheck(
      placed: placed.length,
      missed: missed,
      spilled: spilled,
      difference: (missed + spilled) / mask.filled,
      overlap: shared / TangramGeometry.pieceArea,
    );
  }
}
