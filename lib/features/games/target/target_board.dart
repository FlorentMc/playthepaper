import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/target/target.dart';

/// The number the player is building towards.
class TargetHeader extends StatelessWidget {
  const TargetHeader({super.key, required this.target});

  final int target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Target $target',
      excludeSemantics: true,
      child: Column(
        children: [
          Text('TARGET', style: theme.textTheme.labelSmall),
          Text('$target', style: PaperTheme.display(size: 44, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}

/// One number on the table. The position label doubles as the key to press,
/// and a chosen tile carries a tick as well as its colour.
class TargetTileButton extends StatelessWidget {
  const TargetTileButton({
    super.key,
    required this.tile,
    required this.position,
    required this.isChosen,
    required this.isCursor,
    required this.onPressed,
  });

  final TargetTile tile;

  /// 1-based place on the table, which is also the digit that selects it.
  final int position;
  final bool isChosen;
  final bool isCursor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final background = isChosen ? colors.cellSelected : (tile.isGiven ? colors.cell : colors.cellHighlight);
    final border = isCursor || isChosen ? theme.colorScheme.onSurface : colors.cellBorder;
    return Semantics(
      key: ValueKey('target-tile-${tile.id}'),
      button: onPressed != null,
      enabled: onPressed != null,
      selected: isChosen,
      label: 'Tile $position, ${tile.value}${tile.isGiven ? '' : ', made'}${isChosen ? ', chosen' : ''}',
      excludeSemantics: true,
      child: SizedBox(
        width: 104,
        height: 56,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: background,
            padding: EdgeInsets.zero,
            side: BorderSide(color: border, width: isCursor || isChosen ? 2.5 : 1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  '${tile.value}',
                  style: PaperTheme.display(size: 24, color: theme.colorScheme.onSurface),
                ),
              ),
              Positioned(
                left: 6,
                top: 4,
                child: Text('$position', style: PaperTheme.body(size: 11, weight: 600, color: colors.subtle)),
              ),
              if (isChosen)
                Positioned(
                  right: 4,
                  top: 3,
                  child: Icon(Icons.check, size: 16, color: theme.colorScheme.onSurface),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the four operations. The chosen one is boxed as well as filled.
class TargetOpButton extends StatelessWidget {
  const TargetOpButton({super.key, required this.op, required this.isChosen, required this.onPressed});

  final TargetOp op;
  final bool isChosen;
  final VoidCallback? onPressed;

  static const Map<TargetOp, String> names = {
    TargetOp.add: 'plus',
    TargetOp.subtract: 'minus',
    TargetOp.multiply: 'times',
    TargetOp.divide: 'divided by',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    return Semantics(
      key: ValueKey('target-op-${op.name}'),
      button: onPressed != null,
      enabled: onPressed != null,
      selected: isChosen,
      label: '${names[op]}${isChosen ? ', chosen' : ''}',
      excludeSemantics: true,
      child: SizedBox(
        width: 64,
        height: 48,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: isChosen ? colors.cellSelected : colors.cell,
            padding: EdgeInsets.zero,
            side: BorderSide(color: isChosen ? theme.colorScheme.onSurface : colors.cellBorder, width: isChosen ? 2.5 : 1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          ),
          child: Text(op.symbol, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
        ),
      ),
    );
  }
}

/// The steps made so far, newest last.
class TargetStepList extends StatelessWidget {
  const TargetStepList({super.key, required this.steps, required this.target});

  final List<TargetStep> steps;
  final int target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    if (steps.isEmpty) {
      return Text(
        'Pick a tile, an operation, then another tile.',
        style: theme.textTheme.labelMedium,
        textAlign: TextAlign.center,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          Semantics(
            key: ValueKey('target-step-$i'),
            label: 'Step ${i + 1}, ${steps[i].a} ${TargetOpButton.names[steps[i].op]} ${steps[i].b} '
                'makes ${steps[i].result}${steps[i].result == target ? ', the target' : ''}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}', style: PaperTheme.body(size: 12, weight: 600, color: colors.subtle)),
                  ),
                  Text(
                    steps[i].display,
                    style: PaperTheme.body(
                      size: 17,
                      weight: steps[i].result == target ? 700 : 450,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (steps[i].result == target) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_circle_outline, size: 18, color: colors.correct),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
