import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/theme.dart';
import '../../../engines/fiveclues/fiveclues.dart';

/// Every clue with the connection it was making, marked with the clue that
/// won the puzzle when there was one.
class FiveCluesRevealList extends StatelessWidget {
  const FiveCluesRevealList({super.key, required this.puzzle, this.solvedOnClue});

  final FiveCluesPuzzle puzzle;

  /// The clue the player named the answer on, zero-based, if they did.
  final int? solvedOnClue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < puzzle.clues.length; i++)
          Padding(
            key: ValueKey('fiveclues-reveal-$i'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              label: [
                'Clue ${i + 1}',
                puzzle.clues[i],
                puzzle.explanations[i],
                if (solvedOnClue == i) 'You named it here',
              ].join('. '),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('CLUE ${i + 1}', style: theme.textTheme.labelSmall),
                      if (solvedOnClue == i) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle_outline, size: 14, color: colors.correct),
                        const SizedBox(width: 3),
                        Text('You named it here', style: theme.textTheme.labelSmall),
                      ],
                    ],
                  ),
                  Text(puzzle.clues[i], style: PaperTheme.body(weight: 700)),
                  const SizedBox(height: 2),
                  Text(puzzle.explanations[i], style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The compact reveal on the result screen: the answer, then each clue's link.
class FiveCluesRevealSummary extends StatelessWidget {
  const FiveCluesRevealSummary({super.key, required this.puzzle});

  final FiveCluesPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(puzzle.answer, style: PaperTheme.display(size: 24, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 8),
        for (var i = 0; i < puzzle.clues.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(puzzle.clues[i], style: PaperTheme.body(size: 14, weight: 700)),
                Text(puzzle.explanations[i], style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

/// One cited passage with a link out to the page it came from.
class SourceNote extends StatelessWidget {
  const SourceNote({super.key, required this.source});

  final SourceRef source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“${source.excerpt}”', style: theme.textTheme.bodySmall),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(source.publisher),
            onPressed: () => launchUrl(Uri.parse(source.url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }
}
