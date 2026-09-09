import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../engines/word/word_engine.dart';

/// One tile of the board. A submitted tile pairs its colour with a mark so
/// the state never depends on colour alone.
class WordTile extends StatelessWidget {
  const WordTile({
    super.key,
    required this.size,
    required this.semanticsLabel,
    this.letter,
    this.feedback,
    this.given = false,
  });

  final double size;
  final String semanticsLabel;
  final String? letter;
  final LetterFeedback? feedback;
  final bool given;

  static String feedbackLabel(LetterFeedback f) => switch (f) {
    LetterFeedback.correct => 'in the word and in place',
    LetterFeedback.misplaced => 'in the word, wrong place',
    LetterFeedback.absent => 'not in the word',
  };

  static String? mark(LetterFeedback f) => switch (f) {
    LetterFeedback.correct => '✓',
    LetterFeedback.misplaced => '•',
    LetterFeedback.absent => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final Color background;
    final Color foreground;
    final Color border;
    var borderWidth = 1.0;
    switch (feedback) {
      case LetterFeedback.correct:
        background = colors.correct;
        foreground = colors.onFeedback;
        border = colors.correct;
      case LetterFeedback.misplaced:
        background = colors.misplaced;
        foreground = colors.onFeedback;
        border = colors.misplaced;
      case LetterFeedback.absent:
        background = colors.absent;
        foreground = colors.onFeedback;
        border = colors.absent;
      case null:
        background = given ? colors.cellHighlight : colors.cell;
        foreground = given ? colors.given : theme.colorScheme.onSurface;
        border = letter == null ? colors.rule : colors.cellBorder;
        if (letter != null) borderWidth = 2;
    }
    final symbol = feedback == null ? null : mark(feedback!);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border, width: borderWidth),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                letter ?? '',
                style: PaperTheme.display(size: size * 0.52, color: foreground),
              ),
            ),
            if (symbol != null)
              Positioned(
                right: size * 0.08,
                bottom: size * 0.02,
                child: Text(
                  symbol,
                  style: PaperTheme.body(size: size * 0.26, weight: 600, color: foreground),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The rows of one board: submitted guesses, the row being typed, and the
/// empty rows left. Sizes its tiles to the space available.
class WordBoard extends StatelessWidget {
  const WordBoard({
    super.key,
    required this.puzzle,
    required this.state,
    required this.typed,
    required this.finished,
    required this.shake,
    this.shareLines = const [],
  });

  final WordPuzzle puzzle;
  final WordState state;

  /// The active row, including the given first letter.
  final String typed;

  /// True once play has ended; the active row is hidden.
  final bool finished;
  final Animation<double> shake;

  /// Feedback rows to show when a finished play has no guesses in memory.
  final List<String> shareLines;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = puzzle.length;
        final r = puzzle.maxGuesses;
        // Tiles shrink with the space available (a phone in landscape leaves
        // little height above the keyboard) and never overflow it; the gap
        // shrinks with them.
        final tight = constraints.maxHeight.isFinite && (constraints.maxHeight - _gap * (r - 1)) / r < 24;
        final gap = tight ? 2.0 : _gap;
        final byWidth = (constraints.maxWidth - gap * (n - 1)) / n;
        final byHeight = constraints.maxHeight.isFinite ? (constraints.maxHeight - gap * (r - 1)) / r : byWidth;
        final size = math.min(byWidth, byHeight).clamp(10.0, 64.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : gap),
                child: rows[i].active ? _shaken(_row(rows[i], i, size, gap)) : _row(rows[i], i, size, gap),
              ),
          ],
        );
      },
    );
  }

  Widget _shaken(Widget child) => AnimatedBuilder(
    animation: shake,
    builder: (context, child) {
      final t = shake.value;
      final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 4) * 8 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
    child: child,
  );

  Widget _row(_RowSpec row, int index, double size, double gap) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < puzzle.length; i++)
        Padding(
          padding: EdgeInsets.only(right: i == puzzle.length - 1 ? 0 : gap),
          child: WordTile(
            size: size,
            letter: row.letters[i],
            feedback: row.feedbacks[i],
            given: row.active && i == 0,
            semanticsLabel: _label(row, index, i),
          ),
        ),
    ],
  );

  String _label(_RowSpec row, int r, int i) {
    final parts = ['Row ${r + 1}', 'letter ${i + 1}'];
    final letter = row.letters[i];
    final feedback = row.feedbacks[i];
    if (letter != null) parts.add(letter);
    if (feedback != null) {
      parts.add(WordTile.feedbackLabel(feedback));
    } else if (row.active && i == 0) {
      parts.add('given');
    } else if (letter == null) {
      parts.add('empty');
    }
    return parts.join(', ');
  }

  List<_RowSpec> _rows() {
    final rows = <_RowSpec>[];
    for (var g = 0; g < state.guesses.length; g++) {
      rows.add(_RowSpec(letters: state.guesses[g].split(''), feedbacks: state.feedbacks[g]));
    }
    if (finished && rows.isEmpty) {
      for (var g = 0; g < shareLines.length && g < puzzle.maxGuesses; g++) {
        final feedbacks = _parseLine(shareLines[g]);
        if (feedbacks == null) break;
        final last = g == shareLines.length - 1;
        rows.add(
          _RowSpec(
            letters: last && feedbacks.every((f) => f == LetterFeedback.correct)
                ? puzzle.answer.split('')
                : List.filled(puzzle.length, null),
            feedbacks: feedbacks,
          ),
        );
      }
    }
    if (!finished && !state.isOver) {
      rows.add(
        _RowSpec(
          letters: [for (var i = 0; i < puzzle.length; i++) i < typed.length ? typed[i] : null],
          feedbacks: List.filled(puzzle.length, null),
          active: true,
        ),
      );
    }
    while (rows.length < puzzle.maxGuesses) {
      rows.add(_RowSpec(letters: List.filled(puzzle.length, null), feedbacks: List.filled(puzzle.length, null)));
    }
    return rows;
  }

  List<LetterFeedback>? _parseLine(String line) {
    final feedbacks = <LetterFeedback>[];
    for (final rune in line.runes) {
      switch (rune) {
        case 0x1F7E9:
          feedbacks.add(LetterFeedback.correct);
        case 0x1F7E8:
          feedbacks.add(LetterFeedback.misplaced);
        case 0x2B1C:
          feedbacks.add(LetterFeedback.absent);
        default:
          return null;
      }
    }
    return feedbacks.length == puzzle.length ? feedbacks : null;
  }
}

class _RowSpec {
  const _RowSpec({required this.letters, required this.feedbacks, this.active = false});

  final List<String?> letters;
  final List<LetterFeedback?> feedbacks;
  final bool active;
}
