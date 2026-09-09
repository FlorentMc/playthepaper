import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// How a cell or a tray tile reads at a glance. Every state carries a symbol
/// or a word as well as a colour.
enum CrossmatchMark {
  /// Play is open and nothing has been said about this tile.
  none,

  /// A check marked this placement as wrong.
  wrong,

  /// The submitted grid put the right tile here.
  right,

  /// The verified grid put this tile here and the player did not.
  missed;

  String? get label => switch (this) {
        CrossmatchMark.none => null,
        CrossmatchMark.wrong => 'Not here',
        CrossmatchMark.right => 'Right',
        CrossmatchMark.missed => 'Missed',
      };

  IconData? get icon => switch (this) {
        CrossmatchMark.none => null,
        CrossmatchMark.wrong => Icons.close,
        CrossmatchMark.right => Icons.check,
        CrossmatchMark.missed => Icons.close,
      };
}

/// One cell of the grid: the tile placed in it, or an empty box.
class CrossmatchCell extends StatelessWidget {
  const CrossmatchCell({
    super.key,
    required this.width,
    required this.rowCriterion,
    required this.colCriterion,
    required this.text,
    required this.mark,
    required this.focused,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final String rowCriterion;
  final String colCriterion;

  /// The tile in this cell, or null when it is empty.
  final String? text;
  final CrossmatchMark mark;
  final bool focused;
  final bool selected;
  final VoidCallback? onTap;

  static const double height = 76;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final ink = theme.colorScheme.onSurface;
    final markLabel = mark.label;
    final semantics = [
      '$rowCriterion, $colCriterion',
      text == null ? 'empty' : 'holds $text',
      ?markLabel,
      if (selected) 'picked up',
    ].join(', ');
    final Color border;
    final double borderWidth;
    if (selected) {
      border = ink;
      borderWidth = 2;
    } else if (mark == CrossmatchMark.wrong) {
      border = colors.error;
      borderWidth = 2;
    } else if (focused) {
      border = ink;
      borderWidth = 1.5;
    } else {
      border = colors.cellBorder;
      borderWidth = 1;
    }
    return Semantics(
      label: semantics,
      button: onTap != null,
      selected: selected,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: text == null ? colors.cell : colors.cellHighlight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: border, width: borderWidth),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (text != null)
                    Flexible(
                      child: Text(
                        text!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: ink),
                      ),
                    ),
                  if (mark.icon != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          mark.icon,
                          size: 14,
                          color: mark == CrossmatchMark.right ? colors.correct : colors.error,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            markLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tile waiting in the tray.
class CrossmatchChip extends StatelessWidget {
  const CrossmatchChip({
    super.key,
    required this.text,
    required this.selected,
    required this.focused,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final ink = theme.colorScheme.onSurface;
    final Color border;
    final double borderWidth;
    if (selected) {
      border = ink;
      borderWidth = 2;
    } else if (focused) {
      border = ink;
      borderWidth = 1.5;
    } else {
      border = colors.rule;
      borderWidth = 1;
    }
    return Semantics(
      label: [text, if (selected) 'picked up' else 'not placed'].join(', '),
      button: onTap != null,
      selected: selected,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.cellSelected : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: border, width: borderWidth),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Center(
                widthFactor: 1,
                child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row or column criterion beside the grid.
class CrossmatchLabel extends StatelessWidget {
  const CrossmatchLabel({super.key, required this.text, required this.width, required this.height});

  final String text;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}
