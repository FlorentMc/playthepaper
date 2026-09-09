import 'package:flutter/material.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/linked/linked.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'linked_reveal.dart';

/// Linked Clues: three small sets lead to three answers, and the three
/// answers together lead to one final subject.
class LinkedScreen extends StatefulWidget {
  const LinkedScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Linked Clues',
    paragraphs: [
      'Three small sets of two clues each lead to three answers. Put the three answers together and they point at one '
          'final subject. Solve the sets in any order; a right answer locks green with a tick.',
      'You start with ten points. Each hint costs one, and each wrong guess at the final subject costs one. Whatever '
          'happens, a solved puzzle is worth at least one point. Giving up scores nothing. Most days it goes for eight or more.',
      'Every set has one hint held back, and there is one for the final subject as well. Take them when you are stuck: '
          'a point is a fair price for getting there.',
      'You may try the final subject at any time, even before the sets are done. Spelling is forgiven: capitals, accents, '
          'punctuation and a leading "the" are all ignored, and sensible short forms are accepted.',
      'On a keyboard, Tab moves between the answer boxes and the buttons, and Enter submits whichever box you are in. '
          'When the puzzle is over you see every answer explained, with the sources.',
    ],
  );

  @override
  State<LinkedScreen> createState() => _LinkedScreenState();
}

class _LinkedScreenState extends State<LinkedScreen> {
  late final LinkedPuzzle _puzzle;
  late LinkedState _state;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  final ScrollController _scroll = ScrollController();
  GameResult? _result;
  bool _finishing = false;

  PlayContext get play => widget.play;

  /// The index of the final subject's field, after the three sets.
  static const int _finalIndex = LinkedPuzzle.setCount;

  @override
  void initState() {
    super.initState();
    _puzzle = LinkedPuzzle.parse(play.record.payload, play.record.reveal);
    _controllers = List.generate(_finalIndex + 1, (_) => TextEditingController());
    _focusNodes = List.generate(_finalIndex + 1, (i) => FocusNode(debugLabel: 'linked-$i'));
    _state = _restore();
    _result = play.existingResult();
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  LinkedState _restore() {
    final saved = play.loadProgress();
    if (saved == null) return LinkedState.initial(_puzzle);
    try {
      return LinkedState.fromJson(_puzzle, saved);
    } on FormatException {
      return LinkedState.initial(_puzzle);
    }
  }

  bool get _canPlay => _result == null && !_finishing && !_state.isOver;

  void _submitSet(int index, [String? _]) {
    if (!_canPlay || _state.isSetSolved(index)) return;
    final text = _controllers[index].text.trim();
    if (LinkedText.normalise(text).isEmpty) {
      _focusNodes[index].requestFocus();
      return;
    }
    if (_state.alreadyGuessedAt(index, text)) {
      _say('You have already tried “$text” here');
      return;
    }
    final next = _state.guessSet(index, text);
    if (next.isSetSolved(index)) {
      _controllers[index].clear();
    } else {
      _say('Not “$text”. Try again, or take the hint.');
    }
    _apply(next, focus: next.isSetSolved(index) ? null : index);
  }

  void _submitFinal([String? _]) {
    if (!_canPlay) return;
    final text = _controllers[_finalIndex].text.trim();
    if (LinkedText.normalise(text).isEmpty) {
      _focusNodes[_finalIndex].requestFocus();
      return;
    }
    if (_state.alreadyGuessedFinal(text)) {
      _say('You have already tried “$text”');
      return;
    }
    final next = _state.guessFinal(text);
    _controllers[_finalIndex].clear();
    if (!next.isSolved) _say('Not “$text”. That is a point gone.');
    _apply(next, focus: next.isSolved ? null : _finalIndex);
  }

  Future<void> _hint(int index) async {
    if (!_canPlay || _state.isHintShown(index)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take the hint?'),
        content: const Text('It costs one point, and you keep whatever is left.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Show it')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_canPlay) return;
    _apply(_state.showHint(index), focus: index);
  }

  Future<void> _confirmGiveUp() async {
    if (!_canPlay) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give up?'),
        content: const Text('Every answer is revealed and the puzzle scores nothing.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep trying')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reveal it all')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_canPlay) return;
    _apply(_state.giveUp());
  }

  void _apply(LinkedState next, {int? focus}) {
    if (identical(next, _state)) return;
    setState(() => _state = next);
    if (next.isOver) {
      _scrollToTop();
    } else if (focus != null) {
      _focusNodes[focus].requestFocus();
    }
    _persist(next);
  }

  /// The end of play puts the page back at the top, where the answers are.
  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1600)));
  }

  Future<void> _persist(LinkedState state) async {
    await play.saveProgress(state.toJson());
    if (!mounted || !state.isOver) return;
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing || _result != null) return;
    _finishing = true;
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.isSolved,
      points: _state.points,
      maxPoints: LinkedPuzzle.maxPoints,
      hints: _state.hints,
      shareLines: _state.shareLines(),
      note: _state.summary(),
      isArchivePlay: play.isArchivePlay,
    );
    if (mounted) setState(() => _result = result);
    await play.complete(context, result, revealTitle: 'The links', reveal: _revealSummary());
    // Saving the result clears progress; keep it so the review can show the run.
    await play.saveProgress(_state.toJson());
  }

  Widget _revealSummary() => LinkedRevealSummary(puzzle: _puzzle);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null || _state.isOver;
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: LinkedScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (play.challenge != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text('Friend: ${play.challenge!.summary()}', style: theme.textTheme.labelMedium),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: done ? _finishedBody(context) : _playingBody(context),
            ),
          ),
          if (done) _finishedFooter(context, result) else _controls(context),
        ],
      ),
    );
  }

  List<Widget> _playingBody(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return [
      Text('${_state.solvedSets} OF ${LinkedPuzzle.setCount} SETS SOLVED', style: theme.textTheme.labelSmall),
      const SizedBox(height: 2),
      Text(
        'Worth ${_state.pointsOnOffer} point${_state.pointsOnOffer == 1 ? '' : 's'} now',
        style: PaperTheme.display(size: 20, color: theme.colorScheme.onSurface),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < LinkedPuzzle.setCount; i++) ...[
        _SetCard(
          index: i,
          set: _puzzle.sets[i],
          solved: _state.isSetSolved(i),
          answerGiven: _state.answerGiven(i),
          hintShown: _state.isHintShown(i),
          controller: _controllers[i],
          focusNode: _focusNodes[i],
          onSubmitted: (text) => _submitSet(i, text),
          onHint: _state.isHintShown(i) ? null : () => _hint(i),
        ),
        const SizedBox(height: 10),
      ],
      const Rule(thick: true),
      const SizedBox(height: 10),
      Semantics(
        key: const ValueKey('linked-final'),
        label: 'The link. What do the three answers have in common?',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('THE LINK', style: theme.textTheme.labelSmall),
            Text(
              'What do the three answers have in common?',
              style: PaperTheme.body(size: 16, weight: 700),
            ),
            if (_state.isFinalHintShown)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _HintLine(text: _puzzle.finalHint),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('linked-final-input'),
                    controller: _controllers[_finalIndex],
                    focusNode: _focusNodes[_finalIndex],
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _submitFinal,
                    decoration: const InputDecoration(
                      hintText: 'The link',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('linked-final-guess'),
                  onPressed: _submitFinal,
                  style: FilledButton.styleFrom(minimumSize: const Size(76, 48)),
                  child: const Text('Answer'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _state.wrongFinalGuesses == 0
                        ? 'A wrong answer here costs a point'
                        : '${_state.wrongFinalGuesses} wrong so far',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('linked-final-hint'),
                  onPressed: _state.isFinalHintShown ? null : () => _hint(_finalIndex),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Hint'),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _finishedBody(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return [
      Text((_result?.solved ?? _state.isSolved) ? 'LINKED' : 'THE ANSWERS', style: theme.textTheme.labelSmall),
      // The saved result outlives the progress that produced it.
      Text(_result?.note ?? _state.summary(), style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
      const SizedBox(height: 4),
      Text(
        'Every answer, and how the three of them join up.',
        style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
      ),
      const SizedBox(height: 12),
      const Rule(),
      const SizedBox(height: 12),
      LinkedRevealList(puzzle: _puzzle, state: _state.isOver ? _state : null),
      if (play.record.sources.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('SOURCES', style: theme.textTheme.labelSmall),
        for (final source in play.record.sources) LinkedSourceNote(source: source),
      ],
    ];
  }

  Widget _finishedFooter(BuildContext context, GameResult? result) {
    if (result == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          const Rule(),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('linked-see-result'),
            onPressed: () => play.showResult(context, result, revealTitle: 'The links', reveal: _revealSummary()),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('See result'),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          const Rule(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _state.hints == 0 ? 'No hints taken' : '${_state.hints} hint${_state.hints == 1 ? '' : 's'} taken',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
                ),
              ),
              TextButton(
                key: const ValueKey('linked-giveup'),
                onPressed: _confirmGiveUp,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text('Give up'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One clue set: its two clues, the hint when taken, and either an answer box
/// or the locked answer.
class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.index,
    required this.set,
    required this.solved,
    required this.answerGiven,
    required this.hintShown,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onHint,
  });

  final int index;
  final LinkedSet set;
  final bool solved;
  final String? answerGiven;
  final bool hintShown;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return Semantics(
      key: ValueKey('linked-set-$index'),
      label: [
        'Set ${index + 1}',
        ...set.clues,
        if (hintShown) 'Hint: ${set.hint}',
        if (solved) 'Solved: ${set.answer}' else 'Not yet solved',
      ].join('. '),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: solved ? colors.cellHighlight : colors.cell,
          border: Border.all(color: solved ? colors.correct : colors.rule, width: solved ? 1.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('SET ${index + 1}', style: theme.textTheme.labelSmall),
                const Spacer(),
                if (solved) ...[
                  Icon(Icons.check_circle, size: 16, color: colors.correct),
                  const SizedBox(width: 4),
                  Text('Solved', style: theme.textTheme.labelSmall),
                ],
              ],
            ),
            const SizedBox(height: 4),
            for (final clue in set.clues)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('· $clue', style: theme.textTheme.bodyLarge),
              ),
            if (hintShown)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _HintLine(text: set.hint),
              ),
            const SizedBox(height: 8),
            if (solved)
              Row(
                children: [
                  Icon(Icons.check, size: 18, color: colors.correct),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      answerGiven ?? set.answer,
                      style: PaperTheme.body(size: 18, weight: 700),
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('linked-set-$index-input'),
                      controller: controller,
                      focusNode: focusNode,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: onSubmitted,
                      decoration: InputDecoration(
                        hintText: 'Answer ${index + 1}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: ValueKey('linked-set-$index-check'),
                    onPressed: () => onSubmitted(controller.text),
                    style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
                    child: const Text('Check'),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ValueKey('linked-set-$index-hint'),
                  onPressed: onHint,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(hintShown ? 'Hint taken' : 'Hint'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A hint, marked with a lamp so colour is never the only signal.
class _HintLine extends StatelessWidget {
  const _HintLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lightbulb, size: 16, color: colors.misplaced),
        const SizedBox(width: 6),
        Expanded(child: Text('Hint: $text', style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
