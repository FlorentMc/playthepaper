import 'package:flutter/material.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/correct/correct_engine.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../news/story_link.dart';
import '../../play/play_context.dart';

/// Correct: one detail in a short dispatch has been altered. Find it, then
/// pick the repair. Every wrong pick, in either step, costs an attempt.
class CorrectScreen extends StatefulWidget {
  const CorrectScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Correct',
    paragraphs: [
      'A short dispatch from a real story is shown with one detail altered: a number, a date, a unit or a comparison.',
      'Step one: tap the detail you think is wrong. Step two: choose the figure that should replace it.',
      'The evidence cards below the dispatch hold everything you need. Every wrong pick uses one of your three attempts.',
    ],
  );

  @override
  State<CorrectScreen> createState() => _CorrectScreenState();
}

class _CorrectScreenState extends State<CorrectScreen> {
  late final CorrectPuzzle _puzzle;
  late final CorrectReveal _reveal;
  late CorrectState _state;
  GameResult? _result;
  String? _message;
  bool _completing = false;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = CorrectPuzzle.parse(play.record.payload);
    _reveal = CorrectReveal.parse(play.record.reveal, _puzzle);
    _result = play.existingResult();
    final saved = _result == null ? play.loadProgress() : null;
    _state = saved == null
        ? CorrectState(puzzle: _puzzle, reveal: _reveal)
        : CorrectState.fromJson(saved, puzzle: _puzzle, reveal: _reveal);
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  Future<void> _pickDetail(int index) async {
    final next = _state.pickDetail(index);
    if (identical(next, _state)) return;
    final wrong = next.wrongDetails.length > _state.wrongDetails.length;
    setState(() {
      _state = next;
      _message = wrong ? _notThatOne(next) : 'That is the altered detail. Now choose what should replace it.';
    });
    await play.saveProgress(next.toJson());
    if (next.isOver) await _finish();
  }

  Future<void> _pickOption(int index) async {
    final next = _state.pickOption(index);
    if (identical(next, _state)) return;
    final wrong = next.wrongOptions.length > _state.wrongOptions.length;
    setState(() {
      _state = next;
      _message = wrong ? _notThatOne(next) : null;
    });
    await play.saveProgress(next.toJson());
    if (next.isOver) await _finish();
  }

  String _notThatOne(CorrectState s) {
    final left = s.attemptsLeft;
    if (left <= 0) return 'Not that one · no attempts left';
    return 'Not that one · $left attempt${left == 1 ? '' : 's'} left';
  }

  Future<void> _finish() async {
    if (_completing || _result != null || !_state.isOver) return;
    _completing = true;
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.status == CorrectStatus.won,
      attempts: _state.attempts,
      isArchivePlay: play.isArchivePlay,
    );
    setState(() => _result = result);
    await play.complete(context, result, revealTitle: 'The correction', reveal: _revealView());
  }

  Widget _revealView() => CorrectRevealView(puzzle: _puzzle, reveal: _reveal, url: storyUrlFor(play));

  Widget _messageLine(ThemeData theme, GameColors colors, bool finished) {
    final message = _message;
    if (message == null || finished) return const SizedBox(width: double.infinity);
    final wrong = message.startsWith('Not');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(wrong ? Icons.close : Icons.check, size: 18, color: wrong ? colors.error : colors.correct),
            const SizedBox(width: 6),
            Expanded(child: Text(message, style: theme.textTheme.labelMedium)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final finished = _result != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final step = _state.step;

    final String prompt;
    if (finished) {
      prompt = _result!.solved ? 'Corrected on attempt ${_result!.attempts}.' : 'Not corrected this time.';
    } else if (step == CorrectStep.findDetail) {
      prompt = 'Which detail is wrong?';
    } else {
      prompt = 'What should it say instead?';
    }

    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: CorrectScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          FriendLine(challenge: play.challenge),
          Semantics(
            label: 'Notice: this dispatch contains one altered detail',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.cellHighlight,
                border: Border(left: BorderSide(color: theme.colorScheme.secondary, width: 3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('This dispatch contains one altered detail', style: theme.textTheme.labelLarge),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(prompt, style: DaypencilTheme.display(size: 20, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(
            finished ? 'Attempts used: ${_result!.attempts} of ${_puzzle.maxAttempts}' : 'Attempt ${_state.attempts} of ${_puzzle.maxAttempts}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 12),
          _Dispatch(
            puzzle: _puzzle,
            reveal: _reveal,
            state: _state,
            finished: finished,
            onPick: !finished && step == CorrectStep.findDetail ? _pickDetail : null,
          ),
          if (reduce)
            _messageLine(theme, colors, finished)
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _messageLine(theme, colors, finished),
            ),
          if (!finished && step == CorrectStep.chooseRepair) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < _puzzle.options.length; i++) ...[
              _OptionButton(
                text: _puzzle.options[i],
                struck: _state.wrongOptions.contains(i),
                onPressed: _state.wrongOptions.contains(i) ? null : () => _pickOption(i),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (finished) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => play.showResult(context, _result!, revealTitle: 'The correction', reveal: _revealView()),
              child: const Text('See result'),
            ),
          ],
          const SizedBox(height: 20),
          const Rule(),
          const SizedBox(height: 12),
          for (final e in _puzzle.evidence) ...[
            _EvidenceCard(evidence: e),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Dispatch extends StatelessWidget {
  const _Dispatch({
    required this.puzzle,
    required this.reveal,
    required this.state,
    required this.finished,
    required this.onPick,
  });

  final CorrectPuzzle puzzle;
  final CorrectReveal reveal;
  final CorrectState state;
  final bool finished;
  final void Function(int index)? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final body = theme.textTheme.bodyLarge!;
    final spans = <InlineSpan>[];
    for (final seg in puzzle.segments) {
      if (!seg.isDetail) {
        spans.add(TextSpan(text: seg.text));
        continue;
      }
      final i = seg.detail!;
      if (finished && i == reveal.alteredDetail) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Semantics(
            label: 'Altered detail ${seg.text}, corrected to ${puzzle.options[reveal.correctOption]}',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: seg.text,
                  style: body.copyWith(decoration: TextDecoration.lineThrough, color: colors.subtle),
                ),
                const TextSpan(text: ' → '),
                TextSpan(
                  text: puzzle.options[reveal.correctOption],
                  style: body.copyWith(fontWeight: FontWeight.w700, color: colors.correct),
                ),
              ]),
              style: body,
            ),
          ),
        ));
        continue;
      }
      final struck = state.wrongDetails.contains(i);
      final found = state.detailFound && i == reveal.alteredDetail;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _DetailButton(
          text: seg.text,
          struck: struck,
          found: found,
          onPressed: onPick == null || struck ? null : () => onPick!(i),
        ),
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: body,
      strutStyle: const StrutStyle(fontFamily: DaypencilTheme.bodyFamily, fontSize: 17, height: 2.6, forceStrutHeight: true),
    );
  }
}

class _DetailButton extends StatelessWidget {
  const _DetailButton({required this.text, required this.struck, required this.found, required this.onPressed});

  final String text;
  final bool struck;
  final bool found;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final ink = theme.colorScheme.onSurface;
    final style = theme.textTheme.bodyLarge!.copyWith(
      decoration: struck ? TextDecoration.lineThrough : TextDecoration.underline,
      decorationColor: struck ? colors.subtle : ink,
      color: struck ? colors.subtle : ink,
      fontWeight: found ? FontWeight.w700 : FontWeight.normal,
    );
    final prefix = struck ? '✕ ' : found ? '✓ ' : '';
    final semantics = struck
        ? 'Detail $text, already ruled out'
        : found
            ? 'Detail $text, the altered one'
            : 'Detail $text';
    return Semantics(
      label: semantics,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: found ? colors.cellSelected : colors.cell,
          disabledForegroundColor: struck ? colors.subtle : ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: found ? ink : colors.cellBorder),
          ),
          textStyle: style,
        ),
        child: Text('$prefix$text', style: style),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.text, required this.struck, required this.onPressed});

  final String text;
  final bool struck;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    return Semantics(
      label: struck ? 'Replace with $text, already ruled out' : 'Replace with $text',
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          disabledForegroundColor: colors.subtle,
        ),
        child: Text(
          struck ? '✕ Replace with $text' : 'Replace with $text',
          style: struck ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.evidence});

  final CorrectEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EVIDENCE', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(evidence.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(evidence.text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(evidence.source, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// The corrected sentence with the fix in bold, the explanation, and a link
/// to the story. Shown on the result screen.
class CorrectRevealView extends StatelessWidget {
  const CorrectRevealView({super.key, required this.puzzle, required this.reveal, required this.url});

  final CorrectPuzzle puzzle;
  final CorrectReveal reveal;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            for (final s in reveal.correctedSegments(puzzle))
              TextSpan(
                text: s.text,
                style: s.isDetail ? body.copyWith(fontWeight: FontWeight.w700) : null,
              ),
          ]),
          style: body,
        ),
        const SizedBox(height: 10),
        Text(reveal.explanation, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        StoryLink(url: url),
      ],
    );
  }
}
