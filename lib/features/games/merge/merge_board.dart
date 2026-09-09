import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/merge/merge.dart';

/// The tile board. Every tile carries its own number, so the colours are
/// decoration rather than information, and each cell carries its position and
/// value as a semantic label.
class MergeBoard extends StatelessWidget {
  const MergeBoard({super.key, required this.state, this.markSpawn = true});

  final MergeState state;

  /// Rings the tile that has just appeared. Off for a finished board.
  final bool markSpawn;

  /// The tile shade for [value]: paper for a 2, the accent for a 2048.
  static Color tileColour(BuildContext context, int value) {
    final colors = context.gameColors;
    if (value == 0) return colors.cell;
    final t = (MergeRules.rankOf(value) / 12).clamp(0.0, 1.0);
    return Color.lerp(colors.cellHighlight, Theme.of(context).colorScheme.secondary, t)!;
  }

  /// Ink that reads on [background], in either theme.
  static Color inkOn(BuildContext context, Color background) {
    final scheme = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light ? scheme.surface : scheme.onSurface;
    final dark = scheme.brightness == Brightness.light ? scheme.onSurface : scheme.surface;
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? light : dark;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final size = state.size;
    return LayoutBuilder(
      builder: (context, constraints) {
        const border = 1.5;
        final side = constraints.biggest.shortestSide;
        final inner = side - border * 2;
        final gap = inner * 0.018;
        final extent = (inner - gap * (size + 1)) / size;
        return Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: colors.cellHighlight,
            border: Border.all(color: colors.cellBorder, width: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var r = 0; r < size; r++)
                Padding(
                  padding: EdgeInsets.only(top: gap, bottom: r == size - 1 ? gap : 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var c = 0; c < size; c++)
                        Padding(
                          padding: EdgeInsets.only(left: gap, right: c == size - 1 ? gap : 0),
                          child: _Tile(
                            index: r * size + c,
                            size: size,
                            extent: extent,
                            value: state.tiles[r * size + c],
                            isNew: markSpawn && state.spawned == r * size + c,
                            isMerged: state.merged.contains(r * size + c),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.index,
    required this.size,
    required this.extent,
    required this.value,
    required this.isNew,
    required this.isMerged,
  });

  final int index;
  final int size;
  final double extent;
  final int value;
  final bool isNew;
  final bool isMerged;

  double _fontSize() {
    final digits = value.toString().length;
    final scale = switch (digits) {
      1 => 0.46,
      2 => 0.42,
      3 => 0.34,
      4 => 0.26,
      _ => 0.21,
    };
    return extent * scale;
  }

  String _label() {
    final where = 'Row ${index ~/ size + 1}, column ${index % size + 1}';
    if (value == 0) return '$where, empty';
    final extra = [if (isNew) 'new', if (isMerged) 'merged'];
    return '$where, $value${extra.isEmpty ? '' : ', ${extra.join(', ')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final background = MergeBoard.tileColour(context, value);
    final ink = MergeBoard.inkOn(context, background);
    return Semantics(
      key: ValueKey('merge-cell-$index'),
      label: _label(),
      readOnly: true,
      excludeSemantics: true,
      child: Container(
        width: extent,
        height: extent,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: isNew ? Theme.of(context).colorScheme.secondary : colors.cellBorder,
            width: isNew ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (value != 0)
              Text(
                '$value',
                style: PaperTheme.body(size: _fontSize(), weight: isMerged ? 700 : 600, color: ink),
                maxLines: 1,
              ),
            if (isNew)
              Positioned(
                top: extent * 0.06,
                right: extent * 0.08,
                child: Text(
                  '•',
                  style: PaperTheme.body(size: extent * 0.28, weight: 700, color: ink),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
