import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/quiz/quiz_engine.dart';

/// Five dots, one per question: a green tick when right, a red cross when
/// wrong, an outline while pending. A star precedes the wager when staked.
class QuizProgressStrip extends StatelessWidget {
  const QuizProgressStrip({
    super.key,
    required this.marks,
    required this.count,
    required this.wagerQuestion,
    this.current = -1,
  });

  final QuizMarks marks;
  final int count;
  final int wagerQuestion;

  /// Index of the question on screen, or -1 when none is.
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          if (marks.staked && i == wagerQuestion) ...[
            const Text('⭐', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
          ],
          _Dot(number: i + 1, mark: marks[i], isCurrent: i == current),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.number, required this.mark, required this.isCurrent});

  final int number;
  final bool? mark;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final status = switch (mark) {
      true => 'right',
      false => 'wrong',
      null => isCurrent ? 'current' : 'to come',
    };
    final fill = switch (mark) {
      true => colors.correct,
      false => colors.error,
      null => null,
    };
    return Semantics(
      label: 'Question $number, $status',
      excludeSemantics: true,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: fill == null
              ? Border.all(
                  color: isCurrent ? theme.colorScheme.onSurface : colors.cellBorder,
                  width: isCurrent ? 2.5 : 1.5,
                )
              : null,
        ),
        child: mark == null
            ? Text('$number', style: theme.textTheme.labelMedium)
            : Text(mark! ? '✓' : '✗', style: PaperTheme.body(size: 16, weight: 700, color: colors.onFeedback)),
      ),
    );
  }
}
