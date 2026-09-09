import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/merge/merge.dart';

/// The four slide buttons. Every pointer gesture on the board has one of
/// these as its equal, and the physical arrow keys do the same job.
class MergeArrows extends StatelessWidget {
  const MergeArrows({super.key, required this.onMove, required this.enabled});

  final void Function(MergeDirection direction) onMove;
  final bool enabled;

  static const Map<MergeDirection, IconData> _icons = {
    MergeDirection.left: Icons.arrow_back,
    MergeDirection.up: Icons.arrow_upward,
    MergeDirection.down: Icons.arrow_downward,
    MergeDirection.right: Icons.arrow_forward,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final entry in _icons.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              key: ValueKey('merge-move-${entry.key.slug}'),
              button: true,
              enabled: enabled,
              label: 'Slide ${entry.key.label.toLowerCase()}',
              excludeSemantics: true,
              child: OutlinedButton(
                onPressed: enabled ? () => onMove(entry.key) : null,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(64, 52),
                  splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
                ),
                child: Icon(entry.value, size: 24),
              ),
            ),
          ),
      ],
    );
  }
}

/// One labelled action under the board.
class MergeAction extends StatelessWidget {
  const MergeAction({
    super.key,
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// A small count shown after the label, such as the undos used.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        key: ValueKey('merge-$id'),
        button: true,
        enabled: onPressed != null,
        label: badge == null ? label : '$label, $badge',
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(44, 52),
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(
                badge == null ? label : '$label $badge',
                style: PaperTheme.body(size: 12, weight: 600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Score, best tile and personal best, set like a scoreboard.
class MergeScores extends StatelessWidget {
  const MergeScores({super.key, required this.score, required this.bestTile, required this.best, required this.bestLabel});

  final int score;
  final int bestTile;
  final int best;
  final String bestLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Score(label: 'Score', value: MergeRules.groupDigits(score)),
        _Score(label: 'Best tile', value: bestTile == 0 ? '–' : '$bestTile'),
        _Score(label: bestLabel, value: best == 0 ? '–' : MergeRules.groupDigits(best)),
      ],
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$label $value',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(value, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
            Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
