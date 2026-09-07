import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/theme.dart';
import '../../../engines/quiz/quiz_engine.dart';

/// What is known about an answered question: whether it was right and, while
/// the play is in progress, which option was picked.
class QuizOutcome {
  const QuizOutcome({required this.correct, this.picked});

  final bool correct;
  final int? picked;
}

/// One question: its number, prompt, the optional wager card, four options
/// and, once answered, the explanation.
class QuizQuestionView extends StatelessWidget {
  const QuizQuestionView({
    super.key,
    required this.index,
    required this.puzzle,
    required this.outcome,
    required this.staked,
    this.story,
    this.wagerPoints,
    this.onAnswer,
    this.onStake,
  });

  final int index;
  final QuizPuzzle puzzle;

  /// Null until the question is answered.
  final QuizOutcome? outcome;
  final bool staked;
  final Story? story;

  /// When set, the wager card is shown with this many points in hand.
  final int? wagerPoints;
  final ValueChanged<int>? onAnswer;
  final ValueChanged<bool>? onStake;

  static const letters = ['A', 'B', 'C', 'D'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = puzzle.questions[index];
    final correct = puzzle.answerOf(index);
    final answered = outcome != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Question ${index + 1} of ${puzzle.questions.length}', style: theme.textTheme.labelSmall),
        const SizedBox(height: 6),
        Text(
          question.prompt,
          style: DaypencilTheme.display(size: 22, color: theme.colorScheme.onSurface, height: 1.25),
        ),
        const SizedBox(height: 16),
        if (wagerPoints != null && !answered) ...[
          _WagerCard(points: wagerPoints!, staked: staked, onStake: onStake),
          const SizedBox(height: 16),
        ],
        for (var o = 0; o < question.options.length; o++) ...[
          if (o > 0) const SizedBox(height: 10),
          QuizOptionButton(
            letter: letters[o],
            text: question.options[o],
            mark: !answered
                ? QuizOptionMark.pending
                : o == correct
                ? QuizOptionMark.correct
                : o == outcome!.picked
                ? QuizOptionMark.wrong
                : QuizOptionMark.other,
            picked: outcome?.picked == o,
            onTap: answered || onAnswer == null ? null : () => onAnswer!(o),
          ),
        ],
        if (answered) ...[
          const SizedBox(height: 16),
          _ExplanationCard(
            correct: outcome!.correct,
            stakeNote: staked && index == puzzle.wagerQuestion,
            explanation: puzzle.explanationOf(index),
            story: story,
          ),
        ],
      ],
    );
  }
}

enum QuizOptionMark { pending, correct, wrong, other }

/// A full-width answer button with its letter on the left and, once the
/// question is answered, a tick or cross on the right.
class QuizOptionButton extends StatelessWidget {
  const QuizOptionButton({
    super.key,
    required this.letter,
    required this.text,
    required this.mark,
    this.picked = false,
    this.onTap,
  });

  final String letter;
  final String text;
  final QuizOptionMark mark;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final ink = theme.colorScheme.onSurface;
    final (Color background, Color border, Color foreground, String? symbol) = switch (mark) {
      QuizOptionMark.pending => (theme.colorScheme.surface, colors.cellBorder, ink, null),
      QuizOptionMark.correct => (colors.correct, colors.correct, colors.onFeedback, '✓'),
      QuizOptionMark.wrong => (theme.colorScheme.surface, colors.error, ink, '✗'),
      QuizOptionMark.other => (theme.colorScheme.surface, colors.rule, colors.subtle, null),
    };
    final status = switch (mark) {
      QuizOptionMark.pending => '',
      QuizOptionMark.correct => picked ? ', your answer, right' : ', right answer',
      QuizOptionMark.wrong => ', your answer, wrong',
      QuizOptionMark.other => '',
    };
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '$letter. $text$status',
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: border, width: mark == QuizOptionMark.wrong ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(letter, style: DaypencilTheme.body(size: 16, weight: 700, color: foreground)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(text, style: DaypencilTheme.body(size: 17, color: foreground, height: 1.3)),
                  ),
                  if (symbol != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      symbol,
                      style: DaypencilTheme.body(
                        size: 20,
                        weight: 700,
                        color: mark == QuizOptionMark.wrong ? colors.error : foreground,
                      ),
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

class _WagerCard extends StatelessWidget {
  const _WagerCard({required this.points, required this.staked, required this.onStake});

  final int points;
  final bool staked;
  final ValueChanged<bool>? onStake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WAGER', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              'Stake 1 point? Correct scores 2, wrong loses 1. You have $points point${points == 1 ? '' : 's'}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Stake')),
                ButtonSegment(value: false, label: Text('Keep')),
              ],
              selected: {staked},
              onSelectionChanged: onStake == null ? null : (s) => onStake!(s.first),
              style: SegmentedButton.styleFrom(
                foregroundColor: ink,
                selectedForegroundColor: theme.colorScheme.surface,
                selectedBackgroundColor: ink,
                side: BorderSide(color: ink),
                minimumSize: const Size(48, 48),
                textStyle: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({
    required this.correct,
    required this.stakeNote,
    required this.explanation,
    required this.story,
  });

  final bool correct;
  final bool stakeNote;
  final String explanation;
  final Story? story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final story = this.story;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  correct ? '✓' : '✗',
                  style: DaypencilTheme.body(size: 20, weight: 700, color: correct ? colors.correct : colors.error),
                ),
                const SizedBox(width: 8),
                Text(
                  correct ? 'Right' : 'Not quite',
                  style: DaypencilTheme.display(size: 20, color: theme.colorScheme.onSurface),
                ),
              ],
            ),
            if (stakeNote) ...[
              const SizedBox(height: 2),
              Text(
                correct ? 'Your stake paid off: two points for this one.' : 'That cost you the point you staked.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(explanation, style: theme.textTheme.bodyMedium),
            if (story != null) ...[
              const SizedBox(height: 6),
              Text('${story.headline} · ${story.publisher}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Read the story'),
                  onPressed: () => launchUrl(Uri.parse(story.url), mode: LaunchMode.externalApplication),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
