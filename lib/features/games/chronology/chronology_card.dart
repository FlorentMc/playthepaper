import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// One event card during play: its position, the text, up and down buttons
/// and a drag handle. Every state carries a label as well as a colour.
class ChronologyCard extends StatelessWidget {
  const ChronologyCard({
    super.key,
    required this.index,
    required this.count,
    required this.text,
    required this.locked,
    required this.focused,
    required this.picked,
    required this.onTap,
    required this.onUp,
    required this.onDown,
    required this.dragHandle,
  });

  final int index;
  final int count;
  final String text;
  final bool locked;
  final bool focused;
  final bool picked;
  final VoidCallback? onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final Widget? dragHandle;

  static const double minHeight = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final ink = theme.colorScheme.onSurface;
    final status = locked
        ? 'Placed by a hint'
        : picked
            ? 'Picked up'
            : null;
    final semantics = [
      'Position ${index + 1} of $count',
      text,
      ?status,
    ].join(', ');
    final Color border;
    final double borderWidth;
    if (picked) {
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
      label: semantics,
      button: onTap != null,
      selected: picked,
      excludeSemantics: true,
      child: Material(
        color: picked
            ? colors.cellSelected
            : locked
                ? colors.cellHighlight
                : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border, width: borderWidth),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Center(
                    child: locked
                        ? Icon(Icons.lock_outline, size: 20, color: colors.subtle)
                        : Text('${index + 1}', style: PaperTheme.display(size: 22, color: ink)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(text, style: theme.textTheme.bodyLarge),
                        if (status != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(status, style: theme.textTheme.labelSmall),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!locked) ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('chronology-up-$index'),
                        tooltip: 'Move up',
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: onUp,
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        key: ValueKey('chronology-down-$index'),
                        tooltip: 'Move down',
                        iconSize: 20,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: onDown,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),
                  ?dragHandle,
                ],
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
