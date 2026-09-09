import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/bridges/bridges.dart';

/// The board: bridges painted underneath, one widget per island on top so
/// each carries its own semantics and a whole-cell tap target. Cells are
/// square and fill the shorter side of the space given.
class BridgesBoard extends StatelessWidget {
  const BridgesBoard({
    super.key,
    required this.layout,
    required this.board,
    required this.selected,
    required this.cursor,
    this.onTap,
    this.onBackgroundTap,
  });

  final BridgesLayout layout;

  /// Bridges per pair.
  final List<int> board;
  final int? selected;

  /// The island under the keyboard cursor.
  final int? cursor;
  final void Function(int island)? onTap;
  final VoidCallback? onBackgroundTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final ink = Theme.of(context).colorScheme.onSurface;
    final sel = selected;
    final guides = <int>{};
    if (sel != null) {
      for (final p in layout.pairsOf[sel]) {
        if (board[p] == 0 && !layout.pairs[p].crossings.any((q) => board[q] > 0)) guides.add(p);
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = min(constraints.maxWidth / layout.width, constraints.maxHeight / layout.height);
        final size = Size(cell * layout.width, cell * layout.height);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBackgroundTap,
                  child: CustomPaint(
                    painter: _BridgePainter(
                      layout: layout,
                      board: board,
                      guides: guides,
                      cell: cell,
                      ink: ink,
                      guide: colors.subtle,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < layout.islands.length; i++)
                Positioned(
                  left: layout.islands[i].col * cell,
                  top: layout.islands[i].row * cell,
                  width: cell,
                  height: cell,
                  child: _Island(
                    index: i,
                    layout: layout,
                    board: board,
                    cell: cell,
                    isSelected: sel == i,
                    isReachable: sel != null && sel != i && layout.pairBetween(sel, i) != null,
                    hasCursor: cursor == i,
                    onTap: onTap == null ? null : () => onTap!(i),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Island extends StatelessWidget {
  const _Island({
    required this.index,
    required this.layout,
    required this.board,
    required this.cell,
    required this.isSelected,
    required this.isReachable,
    required this.hasCursor,
    required this.onTap,
  });

  final int index;
  final BridgesLayout layout;
  final List<int> board;
  final double cell;
  final bool isSelected;
  final bool isReachable;
  final bool hasCursor;
  final VoidCallback? onTap;

  BridgesIsland get island => layout.islands[index];

  int get load => layout.load(board, index);

  BridgesIslandStatus get status {
    if (load < island.count) return BridgesIslandStatus.under;
    return load == island.count ? BridgesIslandStatus.complete : BridgesIslandStatus.over;
  }

  String _label() {
    final parts = <String>[];
    for (final p in layout.pairsOf[index]) {
      final n = board[p];
      if (n == 0) continue;
      final pair = layout.pairs[p];
      final side = pair.horizontal ? (pair.a == index ? 'right' : 'left') : (pair.a == index ? 'down' : 'up');
      parts.add('$n $side');
    }
    final bridges = parts.isEmpty ? '' : ': ${parts.join(', ')}';
    final state = switch (status) {
      BridgesIslandStatus.under => '',
      BridgesIslandStatus.complete => ', complete',
      BridgesIslandStatus.over => ', too many',
    };
    final reach = isReachable ? ', in line with the selected island' : '';
    return 'Island row ${island.row + 1}, column ${island.col + 1}, needs ${island.count}, has $load$bridges$state$reach';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final radius = cell * 0.36;
    final Color fill;
    final Color border;
    final Color number;
    switch (status) {
      case BridgesIslandStatus.complete:
        fill = ink;
        border = ink;
        number = theme.colorScheme.surface;
      case BridgesIslandStatus.over:
        fill = isSelected ? colors.cellSelected : colors.cell;
        border = colors.error;
        number = colors.error;
      case BridgesIslandStatus.under:
        fill = isSelected ? colors.cellSelected : colors.cell;
        border = ink;
        number = ink;
    }
    final badge = switch (status) {
      BridgesIslandStatus.complete => Icons.check,
      BridgesIslandStatus.over => Icons.close,
      BridgesIslandStatus.under => null,
    };
    return Semantics(
      key: ValueKey('bridges-island-$index'),
      label: _label(),
      selected: isSelected,
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (hasCursor)
              Container(
                width: cell - 2,
                height: cell - 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cell * 0.18),
                  border: Border.all(color: ink, width: 2),
                ),
              ),
            if (isSelected)
              Container(
                width: radius * 2 + cell * 0.2,
                height: radius * 2 + cell * 0.2,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.cellSelected),
              ),
            Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: border, width: isSelected ? 3 : 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${island.count}',
                style: PaperTheme.body(size: cell * 0.42, weight: 700, color: number, height: 1),
              ),
            ),
            if (badge != null)
              Positioned(
                top: cell * 0.04,
                right: cell * 0.04,
                child: Icon(badge, size: cell * 0.26, color: status == BridgesIslandStatus.over ? colors.error : ink),
              ),
          ],
        ),
      ),
    );
  }
}

class _BridgePainter extends CustomPainter {
  const _BridgePainter({
    required this.layout,
    required this.board,
    required this.guides,
    required this.cell,
    required this.ink,
    required this.guide,
  });

  final BridgesLayout layout;
  final List<int> board;

  /// Pairs from the selected island that could take a bridge, drawn dotted.
  final Set<int> guides;
  final double cell;
  final Color ink;
  final Color guide;

  Offset _centre(int island) {
    final i = layout.islands[island];
    return Offset((i.col + 0.5) * cell, (i.row + 0.5) * cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = cell * 0.36;
    final line = Paint()
      ..color = ink
      ..strokeWidth = max(2.5, cell * 0.06)
      ..strokeCap = StrokeCap.butt;
    final dot = Paint()..color = guide;
    for (final pair in layout.pairs) {
      final count = board[pair.index];
      final a = _centre(pair.a), b = _centre(pair.b);
      final dir = pair.horizontal ? const Offset(1, 0) : const Offset(0, 1);
      final start = a + dir * radius, end = b - dir * radius;
      if (guides.contains(pair.index)) {
        final length = (end - start).distance;
        final step = cell * 0.25;
        for (var t = step / 2; t < length; t += step) {
          canvas.drawCircle(start + dir * t, max(1.2, cell * 0.03), dot);
        }
        continue;
      }
      if (count == 0) continue;
      if (count == 1) {
        canvas.drawLine(start, end, line);
      } else {
        final offset = pair.horizontal ? Offset(0, cell * 0.11) : Offset(cell * 0.11, 0);
        canvas.drawLine(start - offset, end - offset, line);
        canvas.drawLine(start + offset, end + offset, line);
      }
    }
  }

  @override
  bool shouldRepaint(_BridgePainter old) =>
      old.layout != layout ||
      !listEquals(old.board, board) ||
      !setEquals(old.guides, guides) ||
      old.cell != cell ||
      old.ink != ink ||
      old.guide != guide;
}
