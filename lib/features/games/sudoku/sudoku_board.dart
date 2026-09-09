import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/sudoku/sudoku.dart';

/// The 9×9 board. Square, fills its constraints, one widget per cell so
/// every cell carries its own semantics and tap target.
class SudokuBoard extends StatelessWidget {
  const SudokuBoard({
    super.key,
    required this.puzzle,
    required this.values,
    required this.notesAt,
    required this.selected,
    required this.flagged,
    this.onTap,
  });

  final SudokuPuzzle puzzle;
  final List<int> values;
  final Set<int> Function(int index) notesAt;
  final int? selected;

  /// Cells shown as wrong: error colour plus a cross, so colour is not the
  /// only cue.
  final Set<int> flagged;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        final cell = size / 9;
        final sel = selected;
        final selValue = sel == null ? 0 : values[sel];
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Column(
                children: [
                  for (var r = 0; r < 9; r++)
                    Row(
                      children: [
                        for (var c = 0; c < 9; c++)
                          _Cell(
                            index: r * 9 + c,
                            size: cell,
                            value: values[r * 9 + c],
                            notes: notesAt(r * 9 + c),
                            isGiven: puzzle.isGiven(r * 9 + c),
                            isSelected: sel == r * 9 + c,
                            isRelated: sel != null &&
                                sel != r * 9 + c &&
                                (SudokuGrid.rowOf[sel] == r ||
                                    SudokuGrid.colOf[sel] == c ||
                                    SudokuGrid.boxOf[sel] == SudokuGrid.boxOf[r * 9 + c]),
                            isSameNumber: selValue != 0 && sel != r * 9 + c && values[r * 9 + c] == selValue,
                            isFlagged: flagged.contains(r * 9 + c),
                            onTap: onTap == null ? null : () => onTap!(r * 9 + c),
                          ),
                      ],
                    ),
                ],
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _GridPainter(
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
    required this.value,
    required this.notes,
    required this.isGiven,
    required this.isSelected,
    required this.isRelated,
    required this.isSameNumber,
    required this.isFlagged,
    required this.onTap,
  });

  final int index;
  final double size;
  final int value;
  final Set<int> notes;
  final bool isGiven;
  final bool isSelected;
  final bool isRelated;
  final bool isSameNumber;
  final bool isFlagged;
  final VoidCallback? onTap;

  String _label() {
    final where = 'Row ${index ~/ 9 + 1}, column ${index % 9 + 1}';
    if (value != 0) {
      return '$where, $value${isGiven ? ', given' : ''}${isFlagged ? ', wrong' : ''}';
    }
    final marks = notes.isEmpty ? '' : ', notes ${(notes.toList()..sort()).join(' ')}';
    return '$where, empty$marks';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
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
    if (isFlagged) {
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
          style: PaperTheme.body(size: size * 0.52, weight: isGiven ? 700 : 450, color: ink),
        ),
      );
    } else if (notes.isNotEmpty) {
      content = Padding(
        padding: EdgeInsets.all(size * 0.06),
        child: Column(
          children: [
            for (var r = 0; r < 3; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < 3; c++)
                      Expanded(
                        child: Center(
                          child: Text(
                            notes.contains(r * 3 + c + 1) ? '${r * 3 + c + 1}' : '',
                            style: PaperTheme.body(size: size * 0.24, weight: 500, color: colors.subtle),
                          ),
                        ),
                      ),
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
      key: ValueKey('sudoku-cell-$index'),
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
              if (isFlagged)
                Positioned(
                  top: size * 0.04,
                  right: size * 0.06,
                  child: Icon(Icons.close, size: size * 0.24, color: colors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.thin, required this.thick});

  final Color thin;
  final Color thick;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 9;
    final thinPaint = Paint()
      ..color = thin
      ..strokeWidth = 1;
    final thickPaint = Paint()
      ..color = thick
      ..strokeWidth = 2.5;
    for (var k = 0; k <= 9; k++) {
      final paint = k % 3 == 0 ? thickPaint : thinPaint;
      final inset = k == 0 ? paint.strokeWidth / 2 : (k == 9 ? -paint.strokeWidth / 2 : 0);
      final at = k * cell + inset;
      canvas.drawLine(Offset(at, 0), Offset(at, size.height), paint);
      canvas.drawLine(Offset(0, at), Offset(size.width, at), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.thin != thin || old.thick != thick;
}
