import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/crossword/crossword_state.dart';

/// The 5×5 board. Each cell is a real button with a semantics label; wrong
/// letters carry a diagonal slash and revealed letters a small dot, so
/// neither state relies on colour alone.
class CrosswordGrid extends StatelessWidget {
  const CrosswordGrid({
    super.key,
    required this.state,
    required this.onTap,
    this.enabled = true,
  });

  final CrosswordState state;
  final void Function(int cell) onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final puzzle = state.puzzle;
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final entryCells = state.currentEntry.cells.toSet();

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.onSurface, width: 2)),
        child: Column(
          children: [
            for (var r = 0; r < puzzle.size; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < puzzle.size; c++)
                      Expanded(
                        child: _Cell(
                          index: puzzle.indexOf(r, c),
                          state: state,
                          isBlock: puzzle.isBlock(puzzle.indexOf(r, c)),
                          selected: state.selected == puzzle.indexOf(r, c),
                          inEntry: entryCells.contains(puzzle.indexOf(r, c)),
                          colors: colors,
                          onTap: enabled ? () => onTap(puzzle.indexOf(r, c)) : null,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.state,
    required this.isBlock,
    required this.selected,
    required this.inEntry,
    required this.colors,
    required this.onTap,
  });

  final int index;
  final CrosswordState state;
  final bool isBlock;
  final bool selected;
  final bool inEntry;
  final GameColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final puzzle = state.puzzle;
    if (isBlock) {
      return Semantics(
        label: 'Block',
        child: Container(color: theme.colorScheme.onSurface),
      );
    }
    final letter = state.letterAt(index);
    final wrong = state.isWrong(index);
    final revealed = state.isRevealed(index);
    final number = puzzle.numberAt(index);
    final background = selected
        ? colors.cellSelected
        : inEntry
            ? colors.cellHighlight
            : colors.cell;
    final letterColor = wrong
        ? colors.error
        : revealed
            ? colors.subtle
            : theme.colorScheme.onSurface;

    final row = puzzle.rowOf(index) + 1;
    final col = puzzle.colOf(index) + 1;
    final entry = puzzle.entryAt(index, state.direction) ?? puzzle.entryAt(index, state.direction.other)!;
    final label = StringBuffer('${entry.label}, row $row column $col, ');
    label.write(letter == null ? 'empty' : 'letter $letter');
    if (wrong) label.write(', marked wrong');
    if (revealed) label.write(', revealed');
    if (selected) label.write(', selected');

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label.toString(),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            return Container(
              decoration: BoxDecoration(
                color: background,
                border: Border.all(color: colors.cellBorder, width: 0.6),
              ),
              child: Stack(
                children: [
                  if (number != null)
                    Positioned(
                      left: side * 0.06,
                      top: side * 0.02,
                      child: Text(
                        '$number',
                        style: DaypencilTheme.body(size: side * 0.22, weight: 600, color: theme.colorScheme.onSurface),
                      ),
                    ),
                  if (letter != null)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: side * 0.12),
                        child: Text(
                          letter,
                          style: DaypencilTheme.body(size: side * 0.52, weight: 600, color: letterColor),
                        ),
                      ),
                    ),
                  if (wrong)
                    Positioned.fill(
                      child: CustomPaint(painter: _SlashPainter(colors.error)),
                    ),
                  if (revealed)
                    Positioned(
                      right: side * 0.08,
                      bottom: side * 0.08,
                      child: Container(
                        width: side * 0.1,
                        height: side * 0.1,
                        decoration: BoxDecoration(color: colors.subtle, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlashPainter extends CustomPainter {
  const _SlashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width * 0.2, size.height * 0.85), Offset(size.width * 0.8, size.height * 0.15), paint);
  }

  @override
  bool shouldRepaint(_SlashPainter old) => old.color != color;
}
