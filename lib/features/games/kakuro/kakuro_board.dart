import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/kakuro/kakuro.dart';

/// The board. Fills its constraints keeping square cells, one widget per
/// cell so every cell carries its own semantics and tap target. Clue cells
/// show the down sum bottom-left and the across sum top-right, split by a
/// diagonal; a finished run gets a tick, a broken one an exclamation mark.
class KakuroBoard extends StatelessWidget {
  const KakuroBoard({
    super.key,
    required this.grid,
    required this.values,
    required this.notesAt,
    required this.selected,
    required this.flagged,
    required this.conflicts,
    required this.runStatus,
    this.onTap,
  });

  final KakuroGrid grid;
  final List<int> values;
  final Set<int> Function(int index) notesAt;
  final int? selected;

  /// Cells a check marked wrong: error colour plus a cross.
  final Set<int> flagged;

  /// Cells whose digit is repeated in a run: error colour plus a mark.
  final Set<int> conflicts;
  final RunStatus Function(KakuroRun run) runStatus;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = [constraints.maxWidth / grid.width, constraints.maxHeight / grid.height].reduce((a, b) => a < b ? a : b);
        final sel = selected;
        final related = <int>{};
        final activeRuns = <int>{};
        if (sel != null && grid.isWhite(sel)) {
          for (final run in grid.runsThrough(sel)) {
            related.addAll(run.cells);
            activeRuns.add(run.index);
          }
        }
        return SizedBox(
          width: cell * grid.width,
          height: cell * grid.height,
          child: Stack(
            children: [
              Column(
                children: [
                  for (var r = 0; r < grid.height; r++)
                    Row(
                      children: [
                        for (var c = 0; c < grid.width; c++) _cell(grid.indexOf(r, c), cell, sel, related, activeRuns),
                      ],
                    ),
                ],
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: Size(cell * grid.width, cell * grid.height),
                  painter: _GridPainter(
                    width: grid.width,
                    height: grid.height,
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

  Widget _cell(int index, double size, int? sel, Set<int> related, Set<int> activeRuns) {
    final cell = grid.cells[index];
    if (cell.isWhite) {
      return _WhiteCell(
        index: index,
        row: grid.rowOf(index),
        col: grid.colOf(index),
        size: size,
        value: values[index],
        notes: notesAt(index),
        isSelected: sel == index,
        isRelated: sel != index && related.contains(index),
        isFlagged: flagged.contains(index),
        isConflict: conflicts.contains(index),
        onTap: onTap == null ? null : () => onTap!(index),
      );
    }
    KakuroRun? across, down;
    if (cell.isClue) {
      for (final run in grid.runs) {
        if (run.clueCell != index) continue;
        if (run.isAcross) {
          across = run;
        } else {
          down = run;
        }
      }
    }
    return _ClueCell(
      index: index,
      row: grid.rowOf(index),
      col: grid.colOf(index),
      size: size,
      across: across,
      down: down,
      acrossStatus: across == null ? null : runStatus(across),
      downStatus: down == null ? null : runStatus(down),
      acrossActive: across != null && activeRuns.contains(across.index),
      downActive: down != null && activeRuns.contains(down.index),
    );
  }
}

class _WhiteCell extends StatelessWidget {
  const _WhiteCell({
    required this.index,
    required this.row,
    required this.col,
    required this.size,
    required this.value,
    required this.notes,
    required this.isSelected,
    required this.isRelated,
    required this.isFlagged,
    required this.isConflict,
    required this.onTap,
  });

  final int index;
  final int row;
  final int col;
  final double size;
  final int value;
  final Set<int> notes;
  final bool isSelected;
  final bool isRelated;
  final bool isFlagged;
  final bool isConflict;
  final VoidCallback? onTap;

  String _label() {
    final where = 'Row ${row + 1}, column ${col + 1}';
    if (value != 0) {
      final state = isFlagged ? ', wrong' : (isConflict ? ', repeated in its run' : '');
      return '$where, $value$state';
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
    } else if (isRelated) {
      background = colors.cellHighlight;
    } else {
      background = colors.cell;
    }
    final ink = isFlagged || isConflict ? colors.error : theme.colorScheme.onSurface;

    Widget content;
    if (value != 0) {
      content = Center(
        child: Text('$value', style: PaperTheme.body(size: size * 0.52, weight: 500, color: ink)),
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
      key: ValueKey('kakuro-cell-$index'),
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
                )
              else if (isConflict)
                Positioned(
                  top: size * 0.02,
                  right: size * 0.1,
                  child: Text('!', style: PaperTheme.body(size: size * 0.26, weight: 700, color: colors.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClueCell extends StatelessWidget {
  const _ClueCell({
    required this.index,
    required this.row,
    required this.col,
    required this.size,
    required this.across,
    required this.down,
    required this.acrossStatus,
    required this.downStatus,
    required this.acrossActive,
    required this.downActive,
  });

  final int index;
  final int row;
  final int col;
  final double size;
  final KakuroRun? across;
  final KakuroRun? down;
  final RunStatus? acrossStatus;
  final RunStatus? downStatus;
  final bool acrossActive;
  final bool downActive;

  static String statusWord(RunStatus? s) => switch (s) {
        RunStatus.met => ', complete',
        RunStatus.wrong => ', not right',
        _ => '',
      };

  String _label() {
    final where = 'Row ${row + 1}, column ${col + 1}';
    if (across == null && down == null) return '$where, block';
    final parts = <String>[
      if (down != null) '${down!.sum} down over ${down!.length} cells${statusWord(downStatus)}',
      if (across != null) '${across!.sum} across over ${across!.length} cells${statusWord(acrossStatus)}',
    ];
    return '$where, ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.onSurface;
    final ink = theme.colorScheme.surface;
    return Semantics(
      key: ValueKey('kakuro-cell-$index'),
      label: _label(),
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CluePainter(background: background, diagonal: ink, split: across != null || down != null),
          child: Stack(
            children: [
              if (across != null)
                Positioned(
                  top: size * 0.06,
                  right: size * 0.08,
                  child: _ClueText(run: across!, status: acrossStatus, active: acrossActive, size: size, ink: ink),
                ),
              if (down != null)
                Positioned(
                  bottom: size * 0.06,
                  left: size * 0.08,
                  child: _ClueText(run: down!, status: downStatus, active: downActive, size: size, ink: ink),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClueText extends StatelessWidget {
  const _ClueText({required this.run, required this.status, required this.active, required this.size, required this.ink});

  final KakuroRun run;
  final RunStatus? status;
  final bool active;
  final double size;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final mark = switch (status) {
      RunStatus.met => '✓',
      RunStatus.wrong => '!',
      _ => '',
    };
    final style = PaperTheme.body(
      size: size * 0.24,
      weight: active ? 700 : 500,
      color: status == RunStatus.met ? ink.withValues(alpha: 0.7) : ink,
    ).copyWith(decoration: active ? TextDecoration.underline : null, decorationColor: ink);
    return Text('$mark${run.sum}', style: style);
  }
}

class _CluePainter extends CustomPainter {
  const _CluePainter({required this.background, required this.diagonal, required this.split});

  final Color background;
  final Color diagonal;
  final bool split;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (!split) return;
    final paint = Paint()
      ..color = diagonal.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_CluePainter old) => old.background != background || old.diagonal != diagonal || old.split != split;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.width, required this.height, required this.thin, required this.thick});

  final int width;
  final int height;
  final Color thin;
  final Color thick;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / width;
    final thinPaint = Paint()
      ..color = thin
      ..strokeWidth = 1;
    final thickPaint = Paint()
      ..color = thick
      ..strokeWidth = 2.5;
    for (var k = 0; k <= width; k++) {
      final edge = k == 0 || k == width;
      final paint = edge ? thickPaint : thinPaint;
      final inset = k == 0 ? paint.strokeWidth / 2 : (k == width ? -paint.strokeWidth / 2 : 0);
      final at = k * cell + inset;
      canvas.drawLine(Offset(at, 0), Offset(at, size.height), paint);
    }
    for (var k = 0; k <= height; k++) {
      final edge = k == 0 || k == height;
      final paint = edge ? thickPaint : thinPaint;
      final inset = k == 0 ? paint.strokeWidth / 2 : (k == height ? -paint.strokeWidth / 2 : 0);
      final at = k * cell + inset;
      canvas.drawLine(Offset(0, at), Offset(size.width, at), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.thin != thin || old.thick != thick || old.width != width || old.height != height;
}
