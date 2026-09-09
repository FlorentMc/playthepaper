import 'package:flutter/material.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/fiveclues/fiveclues.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'fiveclues_reveal.dart';

/// Five Clues: five clues to one answer, shown one at a time. The earlier
/// you name it, the more it is worth.
class FiveCluesScreen extends StatefulWidget {
  const FiveCluesScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Five Clues',
    paragraphs: [
      'Five clues all point at the same answer. They appear one at a time, hardest first, and you may guess after each one.',
      'Guessing early is worth more: five points on the first clue, four on the second, and so on down to one on the fifth. '
          'A wrong guess is not fatal, it simply brings out the next clue. Most days the answer comes on the third clue.',
      'Type your answer and press Enter, or tap Guess. Spelling is forgiven: capitals, accents, punctuation and a leading '
          '"the" are all ignored, and sensible short forms are accepted.',
      'Next clue brings the following clue out without guessing. On the last clue that button becomes Give up, which ends '
          'the puzzle and reveals the answer.',
      'On a keyboard the answer box has the focus, Enter submits a guess, and Tab reaches Guess, Next clue and the buttons '
          'below. When the puzzle is over you see the answer and how every clue pointed to it, with the sources.',
    ],
  );

  @override
  State<FiveCluesScreen> createState() => _FiveCluesScreenState();
}

class _FiveCluesScreenState extends State<FiveCluesScreen> {
  late final FiveCluesPuzzle _puzzle;
  late FiveCluesState _state;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'fiveclues-guess');
  final ScrollController _scroll = ScrollController();
  GameResult? _result;
  bool _finishing = false;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = FiveCluesPuzzle.parse(play.record.payload, play.record.reveal);
    _state = _restore();
    _result = play.existingResult();
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  FiveCluesState _restore() {
    final saved = play.loadProgress();
    if (saved == null) return FiveCluesState.initial(_puzzle);
    try {
      return FiveCluesState.fromJson(_puzzle, saved);
    } on FormatException {
      return FiveCluesState.initial(_puzzle);
    }
  }

  bool get _canPlay => _result == null && !_finishing && !_state.isOver;

  void _submit([String? _]) {
    if (!_canPlay) return;
    final text = _controller.text.trim();
    if (FiveCluesText.normalise(text).isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (_state.alreadyGuessed(text)) {
      _say('You have already tried “$text”');
      return;
    }
    final next = _state.guess(text);
    _controller.clear();
    _advance(next);
  }

  void _next() {
    if (!_canPlay) return;
    _advance(_state.pass());
  }

  Future<void> _confirmGiveUp() async {
    if (!_canPlay) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give up?'),
        content: const Text('The answer is revealed and this puzzle scores nothing.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep trying')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reveal the answer')),
        ],
      ),
    );
    if (ok != true || !mounted || !_canPlay) return;
    _advance(_state.pass());
  }

  void _advance(FiveCluesState next) {
    if (identical(next, _state)) return;
    setState(() => _state = next);
    _focus.requestFocus();
    _scrollTo(next.isOver ? 0 : null);
    _persist(next);
  }

  /// Moves the page to [offset], or to the newest clue when it is null. The
  /// end of play jumps back to the top, where the answer is.
  void _scrollTo(double? offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = offset ?? _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1500)));
    _focus.requestFocus();
  }

  Future<void> _persist(FiveCluesState state) async {
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
      maxPoints: FiveCluesPuzzle.maxPoints,
      attempts: _state.attempts,
      shareLines: _state.shareLines(),
      note: _state.summary(),
      isArchivePlay: play.isArchivePlay,
    );
    if (mounted) setState(() => _result = result);
    await play.complete(context, result, revealTitle: 'The answer', reveal: _revealSummary());
    // Saving the result clears progress; keep it so the review can show the run.
    await play.saveProgress(_state.toJson());
  }

  Widget _revealSummary() => FiveCluesRevealSummary(puzzle: _puzzle);

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final done = result != null || _state.isOver;
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: FiveCluesScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (play.challenge != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Friend: ${play.challenge!.summary()}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: done ? _finishedBody(context) : _playingBody(context),
            ),
          ),
          if (done) _finishedFooter(context, result) else _input(context),
        ],
      ),
    );
  }

  List<Widget> _playingBody(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return [
      Text(
        'CLUE ${_state.revealed} OF ${FiveCluesPuzzle.clueCount}',
        style: theme.textTheme.labelSmall,
      ),
      const SizedBox(height: 2),
      Text(
        'Name it now for ${_state.pointsOnOffer} point${_state.pointsOnOffer == 1 ? '' : 's'}',
        style: PaperTheme.display(size: 20, color: theme.colorScheme.onSurface),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < _state.revealed; i++) ...[
        _ClueCard(
          index: i,
          text: _puzzle.clues[i],
          latest: i == _state.currentClue,
          guesses: _state.guesses.where((g) => g.clue == i).toList(),
        ),
        const SizedBox(height: 8),
      ],
      if (_state.attempts == 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Guess when you are ready. A wrong guess brings out the next clue.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
          ),
        ),
    ];
  }

  List<Widget> _finishedBody(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    return [
      Text('THE ANSWER', style: theme.textTheme.labelSmall),
      Text(_puzzle.answer, style: PaperTheme.display(size: 30, color: theme.colorScheme.onSurface)),
      const SizedBox(height: 4),
      Text(
        // The saved result outlives the progress that produced it.
        _result?.note ?? _state.summary(),
        style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
      ),
      const SizedBox(height: 12),
      const Rule(),
      const SizedBox(height: 12),
      FiveCluesRevealList(puzzle: _puzzle, solvedOnClue: _state.isOver ? _state.solvedOnClue : null),
      if (play.record.sources.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('SOURCES', style: theme.textTheme.labelSmall),
        for (final source in play.record.sources) SourceNote(source: source),
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
            key: const ValueKey('fiveclues-see-result'),
            onPressed: () => play.showResult(context, result, revealTitle: 'The answer', reveal: _revealSummary()),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('See result'),
          ),
        ],
      ),
    );
  }

  Widget _input(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final last = _state.hasMoreClues ? null : 'last';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Rule(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('fiveclues-input'),
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submit,
                  decoration: const InputDecoration(
                    hintText: 'Your answer',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('fiveclues-guess'),
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(76, 48)),
                child: const Text('Guess'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _state.attempts == 0
                      ? 'No guesses yet'
                      : '${_state.attempts} guess${_state.attempts == 1 ? '' : 'es'} so far',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('fiveclues-next'),
                onPressed: last == null ? _next : _confirmGiveUp,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                icon: Icon(last == null ? Icons.arrow_forward : Icons.visibility_outlined, size: 18),
                label: Text(last == null ? 'Next clue' : 'Give up'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One clue and the guesses made against it.
class _ClueCard extends StatelessWidget {
  const _ClueCard({required this.index, required this.text, required this.latest, required this.guesses});

  final int index;
  final String text;
  final bool latest;
  final List<FiveCluesGuess> guesses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final number = index + 1;
    final worth = FiveCluesPuzzle.pointsForClue(index);
    return Semantics(
      key: ValueKey('fiveclues-clue-$index'),
      label: [
        'Clue $number of ${FiveCluesPuzzle.clueCount}, worth $worth point${worth == 1 ? '' : 's'}',
        text,
        for (final g in guesses) g.correct ? 'Right answer: ${g.text}' : 'Wrong guess: ${g.text}',
      ].join('. '),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: latest ? colors.cellHighlight : colors.cell,
          border: Border.all(color: latest ? colors.cellBorder : colors.rule, width: latest ? 1.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('CLUE $number', style: theme.textTheme.labelSmall),
                const Spacer(),
                Text('$worth pt${worth == 1 ? '' : 's'}', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(text, style: theme.textTheme.bodyLarge),
            for (final guess in guesses)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      guess.correct ? Icons.check_circle_outline : Icons.cancel_outlined,
                      size: 16,
                      color: guess.correct ? colors.correct : colors.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${guess.text} · ${guess.correct ? 'right' : 'not this one'}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
