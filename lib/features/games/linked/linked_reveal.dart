import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/theme.dart';
import '../../../engines/linked/linked.dart';
import '../../../shared/widgets/game_shell.dart';

/// Every set with its answer and the link it was making, then how the three
/// answers point at the final subject.
class LinkedRevealList extends StatelessWidget {
  const LinkedRevealList({super.key, required this.puzzle, this.state});

  final LinkedPuzzle puzzle;

  /// The finished run, when this session still has it.
  final LinkedState? state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < puzzle.sets.length; i++)
          Padding(
            key: ValueKey('linked-reveal-$i'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              label: [
                'Set ${i + 1}, answer ${puzzle.sets[i].answer}',
                puzzle.explanations[i],
                if (state != null) state!.isSetSolved(i) ? 'You had this' : 'You did not get this',
              ].join('. '),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('SET ${i + 1}', style: theme.textTheme.labelSmall),
                      if (state != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          state!.isSetSolved(i) ? Icons.check_circle_outline : Icons.cancel_outlined,
                          size: 14,
                          color: state!.isSetSolved(i) ? colors.correct : colors.error,
                        ),
                        const SizedBox(width: 3),
                        Text(state!.isSetSolved(i) ? 'You had this' : 'You missed this', style: theme.textTheme.labelSmall),
                      ],
                    ],
                  ),
                  Text(puzzle.sets[i].answer, style: PaperTheme.display(size: 20, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(puzzle.explanations[i], style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        const Rule(),
        const SizedBox(height: 10),
        Text('THE LINK', style: theme.textTheme.labelSmall),
        Text(puzzle.finalAnswer, style: PaperTheme.display(size: 24, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 2),
        Text(puzzle.linkExplanation, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// The compact reveal on the result screen: the three answers, the link, and
/// the sentence that ties them together.
class LinkedRevealSummary extends StatelessWidget {
  const LinkedRevealSummary({super.key, required this.puzzle});

  final LinkedPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          [for (final set in puzzle.sets) set.answer].join(' · '),
          style: PaperTheme.body(size: 16, weight: 700),
        ),
        const SizedBox(height: 6),
        Text(puzzle.finalAnswer, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 4),
        Text(puzzle.linkExplanation, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// One cited passage with a link out to the page it came from.
class LinkedSourceNote extends StatelessWidget {
  const LinkedSourceNote({super.key, required this.source});

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
