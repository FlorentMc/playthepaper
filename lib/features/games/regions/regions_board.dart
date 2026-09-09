import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/regions/regions.dart';

/// The board: one widget per cell for its own semantics and tap target,
/// with thin lines between cells and thick borders around each region.
class RegionsBoard extends StatelessWidget {
  const RegionsBoard({
    super.key,
    required this.puzzle,
    required this.values,
    required this.notesAt,
    required this.selected,
    required this.wrong,
    required this.conflicts,
    this.onTap,
  });

  final RegionsPuzzle puzzle;
  final List<int> values;
  final Set<int> Function(int index) notesAt;
  final int? selected;

  /// Cells the last check marked wrong: error colour plus a cross.
  final Set<int> wrong;

  /// Cells breaking a rule right now: error colour plus a cross.
  final Set<int> conflicts;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final grid = puzzle.grid;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(constraints.maxWidth / grid.width, constraints.maxHeight / grid.height);
        final width = cell * grid.width;
        final height = cell * grid.height;
        final sel = selected;
        final selValue = sel == null ? 0 : values[sel];
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Column(
                children: [
                  for (var r = 0; r < grid.height; r++)
                    Row(
                      children: [
                        for (var c = 0; c < grid.width; c++)
                          _Cell(
                            index: r * grid.width + c,
                            grid: grid,
                            size: cell,
                            value: values[r * grid.width + c],
                            notes: notesAt(r * grid.width + c),
                            isGiven: puzzle.isGiven(r * grid.width + c),
                            isSelected: sel == r * grid.width + c,
                            isRelated: sel != null && sel != r * grid.width + c && grid.sameRegion(sel, r * grid.width + c),
                            isSameNumber: selValue != 0 && sel != r * grid.width + c && values[r * grid.width + c] == selValue,
                            isWrong: wrong.contains(r * grid.width + c),
                            isConflict: conflicts.contains(r * grid.width + c),
                            onTap: onTap == null ? null : () => onTap!(r * grid.width + c),
                          ),
                      ],
                    ),
                ],
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _BordersPainter(
                    grid: grid,
                    thin: context.gameColors.cellBorder,
                    thick: Theme.of(context).colorScheme.onSurface,
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

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.grid,
    required this.size,
    required this.value,
    required this.notes,
    required this.isGiven,
    required this.isSelected,
    required this.isRelated,
    required this.isSameNumber,
    required this.isWrong,
    required this.isConflict,
    required this.onTap,
  });

  final int index;
  final RegionsGrid grid;
  final double size;
  final int value;
  final Set<int> notes;
  final bool isGiven;
  final bool isSelected;
  final bool isRelated;
  final bool isSameNumber;
  final bool isWrong;
  final bool isConflict;
  final VoidCallback? onTap;

  String _label() {
    final where = 'Row ${grid.rowOf(index) + 1}, column ${grid.colOf(index) + 1}, region of ${grid.sizeOf(index)}';
    if (value != 0) {
      final state = isGiven
          ? ', given'
          : isWrong
              ? ', wrong'
              : isConflict
                  ? ', conflict'
                  : '';
      return '$where, $value$state';
    }
    final marks = notes.isEmpty ? '' : ', notes ${(notes.toList()..sort()).join(' ')}';
    return '$where, empty$marks';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final flagged = isWrong || isConflict;
    final Color background;
    if (isSelected) {
      background = colors.cellSelected;
    } else if (isSameNumber) {
      background = Color.alphaBlend(colors.cellSelected.withValues(alpha: 0.45), colors.cell);
    } else if (isRelated) {
      background = colors.cellHighlight;
    } else {
      background = colors.cell;
    }
    final Color ink;
    if (flagged) {
      ink = colors.error;
    } else if (isGiven) {
      ink = colors.given;
    } else {
      ink = theme.colorScheme.onSurface;
    }

    Widget content;
    if (value != 0) {
      content = Center(
        child: Text(
          '$value',
          style: PaperTheme.body(size: size * 0.5, weight: isGiven ? 700 : 450, color: ink),
        ),
      );
    } else if (notes.isNotEmpty) {
      content = Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 0.08, vertical: size * 0.12),
        child: Column(
          children: [
            for (final row in const [
              [1, 2, 3],
              [4, 5],
            ])
              Expanded(
                child: Row(
                  children: [
                    for (final d in row)
                      Expanded(
                        child: Center(
                          child: Text(
                            notes.contains(d) ? '$d' : '',
                            style: PaperTheme.body(size: size * 0.24, weight: 500, color: colors.subtle),
                          ),
                        ),
                      ),
                    if (row.length < 3) const Spacer(),
                  ],
                ),
              ),
          ],
        ),
      );
    } else {
      content = const SizedBox.expand();
    }

    return Semantics(
      key: ValueKey('regions-cell-$index'),
      label: _label(),
      selected: isSelected,
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          color: background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (flagged)
                Positioned(
                  top: size * 0.05,
                  right: size * 0.07,
                  child: Icon(Icons.close, size: size * 0.24, color: colors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BordersPainter extends CustomPainter {
  const _BordersPainter({required this.grid, required this.thin, required this.thick});

  final RegionsGrid grid;
  final Color thin;
  final Color thick;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / grid.width;
    final thinPaint = Paint()
      ..color = thin
      ..strokeWidth = 1;
    final thickPaint = Paint()
      ..color = thick
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    for (var k = 1; k < grid.width; k++) {
      canvas.drawLine(Offset(k * cell, 0), Offset(k * cell, size.height), thinPaint);
    }
    for (var k = 1; k < grid.height; k++) {
      canvas.drawLine(Offset(0, k * cell), Offset(size.width, k * cell), thinPaint);
    }
    final inset = thickPaint.strokeWidth / 2;
    for (var r = 0; r < grid.height; r++) {
      for (var c = 0; c < grid.width; c++) {
        final i = r * grid.width + c;
        final left = c * cell, top = r * cell;
        if (c == grid.width - 1 || !grid.sameRegion(i, i + 1)) {
          final x = c == grid.width - 1 ? size.width - inset : left + cell;
          canvas.drawLine(Offset(x, top), Offset(x, top + cell), thickPaint);
        }
        if (r == grid.height - 1 || !grid.sameRegion(i, i + grid.width)) {
          final y = r == grid.height - 1 ? size.height - inset : top + cell;
          canvas.drawLine(Offset(left, y), Offset(left + cell, y), thickPaint);
        }
      }
    }
    canvas.drawLine(Offset(inset, 0), Offset(inset, size.height), thickPaint);
    canvas.drawLine(Offset(0, inset), Offset(size.width, inset), thickPaint);
  }

  @override
  bool shouldRepaint(_BordersPainter old) => old.grid != grid || old.thin != thin || old.thick != thick;
}
