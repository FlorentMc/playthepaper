import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/loop/loop.dart';

/// The board: dots, lines and crosses are painted, the clues and the edges
/// carry the semantics on top. A tap anywhere takes the nearest edge, so the
/// target for an edge is the whole band around it, not the small node that
/// holds its label.
class LoopBoard extends StatelessWidget {
  const LoopBoard({
    super.key,
    required this.puzzle,
    required this.marks,
    required this.satisfied,
    required this.broken,
    required this.branches,
    this.cursor,
    this.onTapEdge,
    this.onCrossEdge,
  });

  final LoopPuzzle puzzle;

  /// One mark per edge.
  final List<EdgeMark> marks;

  /// Clue cells whose count is met.
  final Set<int> satisfied;

  /// Clue cells that can no longer meet their count.
  final Set<int> broken;

  /// Dots where three or more lines meet.
  final Set<int> branches;

  /// The edge under the keyboard cursor.
  final int? cursor;
  final void Function(int edge)? onTapEdge;

  /// A long press marks a cross whatever the current mode.
  final void Function(int edge)? onCrossEdge;

  /// Room around the grid for the outer lines and the cursor ring.
  static const double margin = 14;

  LoopGrid get grid => puzzle.grid;

  int _nearestEdge(Offset local, double cell) {
    final x = (local.dx - margin) / cell;
    final y = (local.dy - margin) / cell;
    final hRow = y.round().clamp(0, grid.height);
    final hCol = x.floor().clamp(0, grid.width - 1);
    final hDistance = (y - hRow).abs() + max(0.0, max(hCol - x, x - hCol - 1));
    final vCol = x.round().clamp(0, grid.width);
    final vRow = y.floor().clamp(0, grid.height - 1);
    final vDistance = (x - vCol).abs() + max(0.0, max(vRow - y, y - vRow - 1));
    return hDistance <= vDistance ? grid.h(hRow, hCol) : grid.v(vRow, vCol);
  }

  /// The rectangle that carries an edge's label and takes a direct tap. The
  /// rectangles never overlap; everything between them falls through to the
  /// nearest-edge hit test underneath.
  Rect _nodeRect(int edge, double cell) {
    final row = grid.edgeRow(edge), col = grid.edgeCol(edge);
    final centre = grid.isHorizontal(edge)
        ? Offset(margin + (col + 0.5) * cell, margin + row * cell)
        : Offset(margin + col * cell, margin + (row + 0.5) * cell);
    final long = cell * 0.7, short = cell * 0.3;
    return Rect.fromCenter(
      center: centre,
      width: grid.isHorizontal(edge) ? long : short,
      height: grid.isHorizontal(edge) ? short : long,
    );
  }

  String _edgeLabel(int edge) {
    final row = grid.edgeRow(edge), col = grid.edgeCol(edge);
    final place = grid.isHorizontal(edge)
        ? (row == grid.height
            ? 'Bottom of row ${grid.height}, column ${col + 1}'
            : 'Top of row ${row + 1}, column ${col + 1}')
        : (col == grid.width
            ? 'Right of row ${row + 1}, column ${grid.width}'
            : 'Left of row ${row + 1}, column ${col + 1}');
    final state = switch (marks[edge]) {
      EdgeMark.empty => 'empty',
      EdgeMark.line => 'line',
      EdgeMark.cross => 'crossed off',
    };
    return '$place, $state';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final lines = List<bool>.generate(grid.edgeCount, (e) => marks[e] == EdgeMark.line, growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = min(
          (constraints.maxWidth - 2 * margin) / grid.width,
          (constraints.maxHeight - 2 * margin) / grid.height,
        ).clamp(24.0, 76.0);
        return SizedBox(
          width: grid.width * cell + 2 * margin,
          height: grid.height * cell + 2 * margin,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onTapEdge == null ? null : (d) => onTapEdge!(_nearestEdge(d.localPosition, cell)),
                  onLongPressStart:
                      onCrossEdge == null ? null : (d) => onCrossEdge!(_nearestEdge(d.localPosition, cell)),
                  child: CustomPaint(
                    painter: _LoopPainter(
                      grid: grid,
                      marks: marks,
                      branches: branches,
                      cursor: cursor,
                      cell: cell,
                      ink: ink,
                      subtle: colors.subtle,
                      error: colors.error,
                      accent: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      for (var c = 0; c < grid.cellCount; c++)
                        if (puzzle.hasClue(c))
                          Positioned(
                            left: margin + grid.cellCol(c) * cell,
                            top: margin + grid.cellRow(c) * cell,
                            width: cell,
                            height: cell,
                            child: _Clue(
                              index: c,
                              clue: puzzle.clueAt(c),
                              lines: LoopRules.lineCount(grid.cellEdges[c], lines),
                              row: grid.cellRow(c),
                              col: grid.cellCol(c),
                              isSatisfied: satisfied.contains(c),
                              isBroken: broken.contains(c),
                              cell: cell,
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              for (var e = 0; e < grid.edgeCount; e++)
                Positioned.fromRect(
                  rect: _nodeRect(e, cell),
                  child: Semantics(
                    key: ValueKey('loop-edge-$e'),
                    container: true,
                    label: _edgeLabel(e),
                    button: onTapEdge != null,
                    selected: cursor == e,
                    onTap: onTapEdge == null ? null : () => onTapEdge!(e),
                    onLongPress: onCrossEdge == null ? null : () => onCrossEdge!(e),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTapEdge == null ? null : () => onTapEdge!(e),
                      onLongPress: onCrossEdge == null ? null : () => onCrossEdge!(e),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Clue extends StatelessWidget {
  const _Clue({
    required this.index,
    required this.clue,
    required this.lines,
    required this.row,
    required this.col,
    required this.isSatisfied,
    required this.isBroken,
    required this.cell,
  });

  final int index;
  final int clue;
  final int lines;
  final int row;
  final int col;
  final bool isSatisfied;
  final bool isBroken;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final ink = Theme.of(context).colorScheme.onSurface;
    final colour = isBroken ? colors.error : (isSatisfied ? colors.subtle : ink);
    final mark = isBroken ? '✕' : (isSatisfied ? '✓' : null);
    final state = isBroken ? ', too many' : (isSatisfied ? ', met' : '');
    return Semantics(
      key: ValueKey('loop-clue-$index'),
      container: true,
      label: 'Row ${row + 1}, column ${col + 1}, clue $clue, $lines line${lines == 1 ? '' : 's'}$state',
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('$clue', style: PaperTheme.body(size: cell * 0.42, weight: 700, color: colour, height: 1)),
          if (mark != null)
            Positioned(
              top: cell * 0.08,
              right: cell * 0.08,
              child: Text(mark, style: PaperTheme.body(size: cell * 0.2, weight: 600, color: colour, height: 1)),
            ),
        ],
      ),
    );
  }
}

class _LoopPainter extends CustomPainter {
  const _LoopPainter({
    required this.grid,
    required this.marks,
    required this.branches,
    required this.cursor,
    required this.cell,
    required this.ink,
    required this.subtle,
    required this.error,
    required this.accent,
  });

  final LoopGrid grid;
  final List<EdgeMark> marks;
  final Set<int> branches;
  final int? cursor;
  final double cell;
  final Color ink;
  final Color subtle;
  final Color error;
  final Color accent;

  Offset _dot(int row, int col) => Offset(LoopBoard.margin + col * cell, LoopBoard.margin + row * cell);

  Offset _from(int edge) => _dot(grid.edgeRow(edge), grid.edgeCol(edge));

  Offset _to(int edge) => grid.isHorizontal(edge)
      ? _dot(grid.edgeRow(edge), grid.edgeCol(edge) + 1)
      : _dot(grid.edgeRow(edge) + 1, grid.edgeCol(edge));

  @override
  void paint(Canvas canvas, Size size) {
    final at = cursor;
    if (at != null) {
      final centre = (_from(at) + _to(at)) / 2;
      final long = cell * 0.86, short = cell * 0.34;
      final rect = Rect.fromCenter(
        center: centre,
        width: grid.isHorizontal(at) ? long : short,
        height: grid.isHorizontal(at) ? short : long,
      );
      final rounded = RRect.fromRectAndRadius(rect, Radius.circular(short / 2));
      canvas.drawRRect(rounded, Paint()..color = accent.withValues(alpha: 0.14));
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final dot = Paint()..color = subtle;
    final branch = Paint()..color = error;
    for (var d = 0; d < grid.dotCount; d++) {
      final row = d ~/ (grid.width + 1), col = d % (grid.width + 1);
      final isBranch = branches.contains(d);
      final radius = max(1.6, cell * (isBranch ? 0.11 : 0.05));
      canvas.drawCircle(_dot(row, col), radius, isBranch ? branch : dot);
      if (isBranch) {
        canvas.drawCircle(
          _dot(row, col),
          radius + 3,
          Paint()
            ..color = error
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    final line = Paint()
      ..color = ink
      ..strokeWidth = max(3, cell * 0.085)
      ..strokeCap = StrokeCap.round;
    final cross = Paint()
      ..color = subtle
      ..strokeWidth = max(1.5, cell * 0.04)
      ..strokeCap = StrokeCap.round;
    for (var e = 0; e < grid.edgeCount; e++) {
      switch (marks[e]) {
        case EdgeMark.empty:
          continue;
        case EdgeMark.line:
          canvas.drawLine(_from(e), _to(e), line);
        case EdgeMark.cross:
          final centre = (_from(e) + _to(e)) / 2;
          final arm = cell * 0.09;
          canvas.drawLine(centre + Offset(-arm, -arm), centre + Offset(arm, arm), cross);
          canvas.drawLine(centre + Offset(arm, -arm), centre + Offset(-arm, arm), cross);
      }
    }
  }

  @override
  bool shouldRepaint(_LoopPainter old) =>
      !listEquals(old.marks, marks) ||
      !setEquals(old.branches, branches) ||
      old.cursor != cursor ||
      old.cell != cell ||
      old.ink != ink ||
      old.subtle != subtle ||
      old.error != error ||
      old.accent != accent;
}
