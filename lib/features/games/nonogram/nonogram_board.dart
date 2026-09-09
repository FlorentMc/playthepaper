import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/nonogram/nonogram.dart';

/// The clues and the grid. Sizes itself to its constraints; one widget per
/// cell so every cell carries its own semantics and tap target, with a pan
/// layer over the grid for painting a run in one stroke.
class NonogramBoard extends StatefulWidget {
  const NonogramBoard({
    super.key,
    required this.puzzle,
    required this.marks,
    this.cursor,
    this.flagged = const {},
    this.rowSatisfied,
    this.columnSatisfied,
    this.finished = false,
    this.showClues = true,
    this.maxCell = 56,
    this.onTap,
    this.onSelectRow,
    this.onStrokeStart,
    this.onStrokeCell,
    this.onStrokeEnd,
  });

  final NonogramPuzzle puzzle;
  final List<CellMark> marks;
  final int? cursor;

  /// Cells a row check found wrong: error colour plus a mark.
  final Set<int> flagged;
  final bool Function(int row)? rowSatisfied;
  final bool Function(int col)? columnSatisfied;

  /// Draws the picture: filled cells solid, everything else plain paper.
  final bool finished;
  final bool showClues;
  final double maxCell;
  final void Function(int index)? onTap;
  final void Function(int row)? onSelectRow;

  /// A stroke begins on the cell where the pointer went down.
  final void Function(int index)? onStrokeStart;
  final void Function(int index)? onStrokeCell;
  final VoidCallback? onStrokeEnd;

  @override
  State<NonogramBoard> createState() => _NonogramBoardState();
}

class _NonogramBoardState extends State<NonogramBoard> {
  int? _downCell;
  int? _strokeStart;
  int? _lastCell;
  _Axis? _axis;
  double _cell = 0;

  NonogramPuzzle get puzzle => widget.puzzle;

  int? _cellAt(Offset local) {
    if (_cell <= 0) return null;
    final c = (local.dx / _cell).floor();
    final r = (local.dy / _cell).floor();
    if (c < 0 || c >= puzzle.width || r < 0 || r >= puzzle.height) return null;
    return r * puzzle.width + c;
  }

  /// Paints [cell] along with any cells the pointer skipped over since the
  /// last one, so a quick drag leaves no gaps.
  void _paint(int cell) {
    final last = _lastCell;
    if (last == cell) return;
    _lastCell = cell;
    if (last == null) {
      widget.onStrokeCell?.call(cell);
      return;
    }
    final step = _axis == _Axis.column ? puzzle.width : 1;
    final lo = last < cell ? last + step : cell;
    final hi = last < cell ? cell : last - step;
    for (var i = lo; i <= hi; i += step) {
      widget.onStrokeCell?.call(i);
    }
  }

  void _paintAt(Offset local) {
    final start = _strokeStart;
    var cell = _cellAt(local);
    if (start == null || cell == null) return;
    final w = puzzle.width;
    if (_axis == null && cell != start) {
      final dr = (cell ~/ w - start ~/ w).abs();
      final dc = (cell % w - start % w).abs();
      _axis = dr > dc ? _Axis.column : _Axis.row;
    }
    if (_axis == _Axis.row) cell = (start ~/ w) * w + cell % w;
    if (_axis == _Axis.column) cell = (cell ~/ w) * w + start % w;
    _paint(cell);
  }

  void _start(DragStartDetails details) {
    final start = _downCell ?? _cellAt(details.localPosition);
    if (start == null) return;
    _strokeStart = start;
    _lastCell = null;
    _axis = null;
    widget.onStrokeStart?.call(start);
    _paint(start);
    _paintAt(details.localPosition);
  }

  void _end() {
    if (_strokeStart != null) widget.onStrokeEnd?.call();
    _strokeStart = null;
    _downCell = null;
    _lastCell = null;
    _axis = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final w = puzzle.width, h = puzzle.height;
    final showClues = widget.showClues;
    final maxRowRuns = max(1, puzzle.rows.fold(0, (m, c) => max(m, c.length)));
    final maxColRuns = max(1, puzzle.cols.fold(0, (m, c) => max(m, c.length)));
    final clueSize = w > 5 ? 13.0 : 15.0;
    // Clue text follows the user's text scale, so the space reserved for it must too.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 3.0);
    final rowClueWidth = showClues ? maxRowRuns * clueSize * 1.2 * textScale + 12 : 0.0;
    final colClueHeight = showClues ? maxColRuns * clueSize * 1.25 * textScale + 12 : 0.0;
    final paints = widget.onStrokeStart != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = [
          (constraints.maxWidth - rowClueWidth) / w,
          (constraints.maxHeight - colClueHeight) / h,
          widget.maxCell,
        ].reduce(min).floorToDouble();
        _cell = cell;
        final gridWidth = cell * w, gridHeight = cell * h;

        Widget grid = Stack(
          children: [
            Column(
              children: [
                for (var r = 0; r < h; r++)
                  Row(
                    children: [
                      for (var c = 0; c < w; c++)
                        _Cell(
                          index: r * w + c,
                          width: w,
                          size: cell,
                          mark: widget.finished
                              ? (puzzle.filledAt(r, c) ? CellMark.filled : CellMark.unknown)
                              : widget.marks[r * w + c],
                          isCursor: !widget.finished && widget.cursor == r * w + c,
                          inCursorLine: !widget.finished &&
                              widget.cursor != null &&
                              widget.cursor != r * w + c &&
                              (widget.cursor! ~/ w == r || widget.cursor! % w == c),
                          isFlagged: widget.flagged.contains(r * w + c),
                          finished: widget.finished,
                          onTap: widget.onTap == null ? null : () => widget.onTap!(r * w + c),
                        ),
                    ],
                  ),
              ],
            ),
            IgnorePointer(
              child: CustomPaint(
                size: Size(gridWidth, gridHeight),
                painter: _GridPainter(width: w, height: h, thin: colors.cellBorder, thick: theme.colorScheme.onSurface),
              ),
            ),
          ],
        );
        if (paints) {
          grid = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanDown: (d) => _downCell = _cellAt(d.localPosition),
            onPanStart: _start,
            onPanUpdate: (d) => _paintAt(d.localPosition),
            onPanEnd: (_) => _end(),
            onPanCancel: _end,
            child: grid,
          );
        }

        return SizedBox(
          width: rowClueWidth + gridWidth,
          height: colClueHeight + gridHeight,
          child: Column(
            children: [
              if (showClues)
                Row(
                  children: [
                    SizedBox(width: rowClueWidth, height: colClueHeight),
                    for (var c = 0; c < w; c++)
                      _ColumnClue(
                        col: c,
                        runs: puzzle.cols[c],
                        width: cell,
                        height: colClueHeight,
                        fontSize: clueSize,
                        satisfied: widget.finished || (widget.columnSatisfied?.call(c) ?? false),
                        highlighted: !widget.finished && widget.cursor != null && widget.cursor! % w == c,
                      ),
                  ],
                ),
              Row(
                children: [
                  if (showClues)
                    Column(
                      children: [
                        for (var r = 0; r < h; r++)
                          _RowClue(
                            row: r,
                            runs: puzzle.rows[r],
                            width: rowClueWidth,
                            height: cell,
                            fontSize: clueSize,
                            satisfied: widget.finished || (widget.rowSatisfied?.call(r) ?? false),
                            highlighted: !widget.finished && widget.cursor != null && widget.cursor! ~/ w == r,
                            onTap: widget.onSelectRow == null ? null : () => widget.onSelectRow!(r),
                          ),
                      ],
                    ),
                  grid,
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _Axis { row, column }

String _runsLabel(List<int> runs) => runs.isEmpty ? '0' : runs.join(', ');

class _RowClue extends StatelessWidget {
  const _RowClue({
    required this.row,
    required this.runs,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.satisfied,
    required this.highlighted,
    required this.onTap,
  });

  final int row;
  final List<int> runs;
  final double width;
  final double height;
  final double fontSize;
  final bool satisfied;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    return Semantics(
      key: ValueKey('nonogram-row-clue-$row'),
      label: 'Row ${row + 1}, clue ${_runsLabel(runs)}${satisfied ? ', done' : ''}',
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: width,
          height: height,
          color: highlighted ? colors.cellSelected : null,
          padding: const EdgeInsets.only(right: 6),
          alignment: Alignment.centerRight,
          child: Text(
            runs.isEmpty ? '0' : runs.join(' '),
            style: PaperTheme.body(
              size: fontSize,
              weight: satisfied ? 500 : 700,
              color: satisfied ? colors.subtle : theme.colorScheme.onSurface,
            ).copyWith(decoration: satisfied ? TextDecoration.lineThrough : null, height: 1),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

class _ColumnClue extends StatelessWidget {
  const _ColumnClue({
    required this.col,
    required this.runs,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.satisfied,
    required this.highlighted,
  });

  final int col;
  final List<int> runs;
  final double width;
  final double height;
  final double fontSize;
  final bool satisfied;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final style = PaperTheme.body(
      size: fontSize,
      weight: satisfied ? 500 : 700,
      color: satisfied ? colors.subtle : theme.colorScheme.onSurface,
    ).copyWith(decoration: satisfied ? TextDecoration.lineThrough : null, height: 1.2);
    return Semantics(
      label: 'Column ${col + 1}, clue ${_runsLabel(runs)}${satisfied ? ', done' : ''}',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        color: highlighted ? colors.cellSelected : null,
        padding: const EdgeInsets.only(bottom: 4),
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (runs.isEmpty) Text('0', style: style) else for (final run in runs) Text('$run', style: style),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.index,
    required this.width,
    required this.size,
    required this.mark,
    required this.isCursor,
    required this.inCursorLine,
    required this.isFlagged,
    required this.finished,
    required this.onTap,
  });

  final int index;
  final int width;
  final double size;
  final CellMark mark;
  final bool isCursor;
  final bool inCursorLine;
  final bool isFlagged;
  final bool finished;
  final VoidCallback? onTap;

  String _label() {
    final where = 'Row ${index ~/ width + 1}, column ${index % width + 1}';
    final what = switch (mark) {
      CellMark.filled => 'filled',
      CellMark.crossed => 'crossed',
      CellMark.unknown => 'blank',
    };
    return '$where, $what${isFlagged ? ', marked wrong' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final Color background;
    if (mark == CellMark.filled) {
      background = ink;
    } else if (isCursor) {
      background = colors.cellSelected;
    } else if (inCursorLine) {
      background = colors.cellHighlight;
    } else {
      background = colors.cell;
    }
    return Semantics(
      key: ValueKey('nonogram-cell-$index'),
      label: _label(),
      selected: isCursor,
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: background,
            border: isFlagged
                ? Border.all(color: colors.error, width: 2)
                : isCursor
                    ? Border.all(color: ink, width: 2)
                    : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (mark == CellMark.crossed && !finished)
                Center(child: Icon(Icons.close, size: size * 0.55, color: colors.subtle)),
              if (isFlagged)
                Positioned(
                  top: 1,
                  right: 2,
                  child: Text(
                    '!',
                    style: PaperTheme.body(
                      size: size * 0.4,
                      weight: 700,
                      color: mark == CellMark.filled ? colors.onFeedback : colors.error,
                    ).copyWith(height: 1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.width, required this.height, required this.thin, required this.thick});

  final int width;
  final int height;
  final Color thin;
  final Color thick;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / width;
    final cellH = size.height / height;
    final thinPaint = Paint()
      ..color = thin
      ..strokeWidth = 1;
    final thickPaint = Paint()
      ..color = thick
      ..strokeWidth = 2;
    bool heavy(int k, int n) => k == 0 || k == n || (n > 5 && k % 5 == 0);
    for (var k = 0; k <= width; k++) {
      final paint = heavy(k, width) ? thickPaint : thinPaint;
      final inset = k == 0 ? paint.strokeWidth / 2 : (k == width ? -paint.strokeWidth / 2 : 0);
      final x = k * cellW + inset;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var k = 0; k <= height; k++) {
      final paint = heavy(k, height) ? thickPaint : thinPaint;
      final inset = k == 0 ? paint.strokeWidth / 2 : (k == height ? -paint.strokeWidth / 2 : 0);
      final y = k * cellH + inset;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.width != width || old.height != height || old.thin != thin || old.thick != thick;
}
