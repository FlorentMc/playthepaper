import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/binary/binary.dart';

/// The square board. One widget per cell so every cell carries its own
/// semantics and tap target; symbols are ● for 1 and ○ for 0, so colour
/// never carries the value on its own.
class BinaryBoard extends StatelessWidget {
  const BinaryBoard({
    super.key,
    required this.puzzle,
    required this.values,
    required this.selected,
    required this.conflicts,
    required this.flagged,
    this.onTap,
  });

  final BinaryPuzzle puzzle;
  final List<int> values;
  final int? selected;

  /// Cells breaking a rule as the grid stands, marked with a !.
  final Set<int> conflicts;

  /// Cells a check found wrong, marked with a cross.
  final Set<int> flagged;
  final void Function(int index)? onTap;

  static String symbol(int value) => value == 1 ? '●' : (value == 0 ? '○' : '');

  static String symbolName(int value) => value == 1 ? 'filled circle' : (value == 0 ? 'hollow circle' : 'empty');

  @override
  Widget build(BuildContext context) {
    final size = puzzle.size;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final cell = side / size;
        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            children: [
              Column(
                children: [
                  for (var r = 0; r < size; r++)
                    Row(
                      children: [
                        for (var c = 0; c < size; c++)
                          _Cell(
                            index: r * size + c,
                            size: size,
                            extent: cell,
                            value: values[r * size + c],
                            isGiven: puzzle.isGiven(r * size + c),
                            isSelected: selected == r * size + c,
                            isConflict: conflicts.contains(r * size + c),
                            isFlagged: flagged.contains(r * size + c),
                            onTap: onTap == null ? null : () => onTap!(r * size + c),
                          ),
                      ],
                    ),
                ],
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: Size.square(side),
                  painter: _GridPainter(
                    size: size,
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
    required this.size,
    required this.extent,
    required this.value,
    required this.isGiven,
    required this.isSelected,
    required this.isConflict,
    required this.isFlagged,
    required this.onTap,
  });

  final int index;
  final int size;
  final double extent;
  final int value;
  final bool isGiven;
  final bool isSelected;
  final bool isConflict;
  final bool isFlagged;
  final VoidCallback? onTap;

  String _label() {
    final where = 'Row ${index ~/ size + 1}, column ${index % size + 1}';
    final what = BinaryBoard.symbolName(value);
    final extra = [
      if (isGiven) 'given',
      if (isFlagged) 'wrong',
      if (isConflict && !isFlagged) 'breaks a rule',
    ];
    return '$where, $what${extra.isEmpty ? '' : ', ${extra.join(', ')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final Color background;
    if (isSelected) {
      background = colors.cellSelected;
    } else if (isGiven) {
      background = colors.cellHighlight;
    } else {
      background = colors.cell;
    }
    final Color ink;
    if (isFlagged || isConflict) {
      ink = colors.error;
    } else if (isGiven) {
      ink = colors.given;
    } else {
      ink = theme.colorScheme.onSurface;
    }
    final mark = isFlagged ? Icons.close : (isConflict ? Icons.priority_high : null);

    return Semantics(
      key: ValueKey('binary-cell-$index'),
      label: _label(),
      selected: isSelected,
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: extent,
          height: extent,
          color: background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  BinaryBoard.symbol(value),
                  style: PaperTheme.body(size: extent * (isGiven ? 0.56 : 0.46), weight: isGiven ? 700 : 450, color: ink),
                ),
              ),
              if (mark != null)
                Positioned(
                  top: extent * 0.04,
                  right: extent * 0.06,
                  child: Icon(mark, size: extent * 0.26, color: colors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.size, required this.thin, required this.thick});

  final int size;
  final Color thin;
  final Color thick;

  @override
  void paint(Canvas canvas, Size area) {
    final cell = area.width / size;
    final thinPaint = Paint()
      ..color = thin
      ..strokeWidth = 1;
    final thickPaint = Paint()
      ..color = thick
      ..strokeWidth = 2.5;
    for (var k = 0; k <= size; k++) {
      final edge = k == 0 || k == size;
      final paint = edge ? thickPaint : thinPaint;
      final inset = k == 0 ? paint.strokeWidth / 2 : (k == size ? -paint.strokeWidth / 2 : 0);
      final at = k * cell + inset;
      canvas.drawLine(Offset(at, 0), Offset(at, area.height), paint);
      canvas.drawLine(Offset(0, at), Offset(area.width, at), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.size != size || old.thin != thin || old.thick != thick;
}
