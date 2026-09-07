import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/letters/letters.dart';

/// The current rank, the points, and one dot per rank along a line.
class LettersRankBar extends StatelessWidget {
  const LettersRankBar({super.key, required this.points, required this.maxScore});

  final int points;
  final int maxScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final rank = LettersRank.rankFor(points, maxScore);
    final next = rank.next;
    final label = '${rank.label} · $points point${points == 1 ? '' : 's'}';
    final nextLabel = next == null ? 'Every rank reached' : '${next.label} at ${next.threshold(maxScore)}';
    return Semantics(
      container: true,
      label: 'Rank ${rank.label}, $points of $maxScore points. ${next == null ? nextLabel : 'Next: $nextLabel'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
                Text(nextLabel, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < LettersRank.values.length; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Container(height: 2, color: i <= rank.index ? theme.colorScheme.onSurface : colors.rule),
                    ),
                  _Dot(reached: i <= rank.index, current: i == rank.index),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.reached, required this.current});

  final bool reached;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final size = current ? 14.0 : 10.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? theme.colorScheme.onSurface : theme.colorScheme.surface,
        border: Border.all(color: reached ? theme.colorScheme.onSurface : colors.cellBorder, width: 1.5),
      ),
    );
  }
}
