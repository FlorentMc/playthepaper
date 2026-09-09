import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/tangram/tangram.dart';

/// The silhouette with the pieces laid on it. The board is always
/// [TangramGeometry.boardUnits] units square; everything is drawn in units and
/// scaled to whatever room there is.
class TangramBoard extends StatelessWidget {
  const TangramBoard({
    super.key,
    required this.puzzle,
    required this.placed,
    this.selected,
    this.dragging,
    this.dragAt,
    this.finished = false,
    this.onTapUnits,
    this.onDragPiece,
    this.onDragTo,
    this.onDragEnd,
  });

  final TangramPuzzle puzzle;
  final Map<TangramPiece, TangramPlacement> placed;
  final TangramPiece? selected;

  /// The piece being dragged, drawn at [dragAt] rather than its placement.
  final TangramPiece? dragging;
  final Offset? dragAt;

  /// Draws the published arrangement, for a puzzle that is already done.
  final bool finished;

  final void Function(Offset units)? onTapUnits;

  /// Called when a drag starts on a placed piece, with the piece under the
  /// finger and where the finger sits inside it.
  final void Function(TangramPiece piece, Offset grabOffset)? onDragPiece;
  final void Function(Offset units)? onDragTo;
  final VoidCallback? onDragEnd;

  static const double _units = TangramGeometry.boardUnits + 0.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final shown = finished
        ? {for (final placement in puzzle.solution) placement.piece: placement}
        : placed;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final scale = side / _units;
        Offset toUnits(Offset local) => Offset(local.dx / scale, local.dy / scale);
        return SizedBox(
          key: const ValueKey('tangram-board'),
          width: side,
          height: side,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: onTapUnits == null ? null : (d) => onTapUnits!(toUnits(d.localPosition)),
            onPanStart: onDragPiece == null
                ? null
                : (d) {
                    final units = toUnits(d.localPosition);
                    final piece = pieceAt(shown, units, selected: selected);
                    if (piece == null) return;
                    final placement = shown[piece]!;
                    onDragPiece!(piece, units - Offset(placement.x.toDouble(), placement.y.toDouble()));
                  },
            onPanUpdate: onDragTo == null ? null : (d) => onDragTo!(toUnits(d.localPosition)),
            onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BoardPainter(
                      puzzle: puzzle,
                      placed: shown,
                      selected: finished ? null : selected,
                      dragging: dragging,
                      dragAt: dragAt,
                      colors: colors,
                      accent: theme.colorScheme.secondary,
                    ),
                  ),
                ),
                for (final entry in shown.entries)
                  _pieceSemantics(entry.key, entry.value, scale, entry.key == selected),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pieceSemantics(TangramPiece piece, TangramPlacement placement, double scale, bool isSelected) {
    final corners = placement.polygon();
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final corner in corners) {
      left = corner.x < left ? corner.x : left;
      right = corner.x > right ? corner.x : right;
      top = corner.y < top ? corner.y : top;
      bottom = corner.y > bottom ? corner.y : bottom;
    }
    return Positioned(
      left: left * scale,
      top: top * scale,
      width: (right - left) * scale,
      height: (bottom - top) * scale,
      child: IgnorePointer(
        child: Semantics(
          label: '${piece.label} at column ${placement.x}, row ${placement.y}, '
              'turned ${placement.degrees} degrees'
              '${placement.flipped ? ', turned over' : ''}'
              '${isSelected ? ', selected' : ''}',
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// The painting order: pieces in their fixed order, the selected one last
  /// so it is drawn on top. Hit testing walks the same list from the top.
  static List<TangramPiece> stackingOrder(Map<TangramPiece, TangramPlacement> placed, TangramPiece? selected) => [
        for (final piece in TangramPiece.values)
          if (placed.containsKey(piece) && piece != selected) piece,
        if (selected != null && placed.containsKey(selected)) selected,
      ];

  /// The topmost visible placed piece under [units], or null. Uses the same
  /// stacking as the painter, so the piece the player sees is the one picked.
  static TangramPiece? pieceAt(Map<TangramPiece, TangramPlacement> placed, Offset units, {TangramPiece? selected}) {
    for (final piece in stackingOrder(placed, selected).reversed) {
      if (TangramGeometry.contains(placed[piece]!.polygon(), units.dx, units.dy)) return piece;
    }
    return null;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.puzzle,
    required this.placed,
    required this.selected,
    required this.dragging,
    required this.dragAt,
    required this.colors,
    required this.accent,
  });

  final TangramPuzzle puzzle;
  final Map<TangramPiece, TangramPlacement> placed;
  final TangramPiece? selected;
  final TangramPiece? dragging;
  final Offset? dragAt;
  final GameColors colors;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / TangramBoard._units;
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.cellHighlight);

    final silhouette = Path()..fillType = PathFillType.evenOdd;
    for (final loop in puzzle.outline) {
      silhouette.moveTo(loop.first.x * scale, loop.first.y * scale);
      for (final corner in loop.skip(1)) {
        silhouette.lineTo(corner.x * scale, corner.y * scale);
      }
      silhouette.close();
    }
    canvas.drawPath(silhouette, Paint()..color = colors.given);

    for (final piece in TangramBoard.stackingOrder(placed, selected)) {
      final placement = placed[piece]!;
      final offset = piece == dragging && dragAt != null
          ? dragAt! - Offset(placement.x.toDouble(), placement.y.toDouble())
          : Offset.zero;
      _drawPiece(canvas, placement, scale, offset, piece == selected);
    }
  }

  void _drawPiece(Canvas canvas, TangramPlacement placement, double scale, Offset shift, bool isSelected) {
    final path = Path();
    final corners = placement.polygon();
    for (var i = 0; i < corners.length; i++) {
      final x = (corners[i].x + shift.dx) * scale;
      final y = (corners[i].y + shift.dy) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = isSelected ? colors.cellSelected : colors.cell);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 1.2
        ..color = isSelected ? accent : colors.cellBorder,
    );
    if (isSelected) {
      final centre = Offset((placement.x + shift.dx) * scale, (placement.y + shift.dy) * scale);
      canvas.drawCircle(centre, 3.5, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.puzzle != puzzle ||
      old.selected != selected ||
      old.dragging != dragging ||
      old.dragAt != dragAt ||
      old.colors != colors ||
      !_samePlacements(old.placed, placed);

  static bool _samePlacements(Map<TangramPiece, TangramPlacement> a, Map<TangramPiece, TangramPlacement> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// One piece drawn on its own, for the tray and the drag feedback.
class TangramPieceIcon extends StatelessWidget {
  const TangramPieceIcon({
    super.key,
    required this.piece,
    required this.size,
    this.rotation = 0,
    this.flipped = false,
    this.selected = false,
    this.faded = false,
  });

  final TangramPiece piece;
  final double size;
  final int rotation;
  final bool flipped;
  final bool selected;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PiecePainter(
          placement: TangramPlacement(piece: piece, x: 0, y: 0, rotation: rotation, flipped: flipped),
          fill: faded ? colors.cellHighlight : (selected ? colors.cellSelected : colors.cell),
          stroke: selected ? Theme.of(context).colorScheme.secondary : colors.cellBorder,
          strokeWidth: selected ? 2.5 : 1.2,
        ),
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({
    required this.placement,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final TangramPlacement placement;
  final Color fill;
  final Color stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 4.4;
    final path = Path();
    final corners = placement.polygon();
    for (var i = 0; i < corners.length; i++) {
      final point = Offset(
        size.width / 2 + corners[i].x * scale,
        size.height / 2 + corners[i].y * scale,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(_PiecePainter old) =>
      old.placement != placement ||
      old.fill != fill ||
      old.stroke != stroke ||
      old.strokeWidth != strokeWidth;
}
