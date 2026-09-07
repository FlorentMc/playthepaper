import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/letters/letters.dart';

/// Every accepted word grouped by length, with the found ones ticked and
/// pangrams starred. Used on the result screen and the finished board.
class LettersAnswerList extends StatelessWidget {
  const LettersAnswerList({super.key, required this.puzzle, required this.found});

  final LettersPuzzle puzzle;
  final Set<String> found;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final byLength = <int, List<String>>{};
    for (final word in puzzle.answers) {
      byLength.putIfAbsent(word.length, () => []).add(word);
    }
    final lengths = byLength.keys.toList()..sort();
    final foundCount = puzzle.answers.where(found.contains).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$foundCount of ${puzzle.answers.length} words found · ✓ found · ★ pangram',
          style: theme.textTheme.bodySmall,
        ),
        for (final length in lengths) ...[
          const SizedBox(height: 12),
          Text(
            '$length LETTERS · ${byLength[length]!.where(found.contains).length}/${byLength[length]!.length}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final word in byLength[length]!..sort())
                _AnswerWord(
                  word: word,
                  found: found.contains(word),
                  pangram: puzzle.isPangramWord(word),
                  inkFound: theme.colorScheme.onSurface,
                  inkMissed: colors.subtle,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AnswerWord extends StatelessWidget {
  const _AnswerWord({
    required this.word,
    required this.found,
    required this.pangram,
    required this.inkFound,
    required this.inkMissed,
  });

  final String word;
  final bool found;
  final bool pangram;
  final Color inkFound;
  final Color inkMissed;

  @override
  Widget build(BuildContext context) {
    final marks = '${found ? '✓ ' : ''}${pangram ? '★ ' : ''}';
    return Semantics(
      label: '$word${pangram ? ', pangram' : ''}${found ? ', found' : ', missed'}',
      child: ExcludeSemantics(
        child: Text(
          '$marks$word',
          style: DaypencilTheme.body(
            size: 15,
            weight: pangram || found ? 600 : 400,
            color: found ? inkFound : inkMissed,
          ),
        ),
      ),
    );
  }
}
