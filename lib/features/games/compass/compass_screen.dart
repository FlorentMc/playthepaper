import 'package:flutter/material.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/compass/compass_engine.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';

/// Word Compass: find the hidden word. Every guess is ranked by how close its
/// meaning is to the target, from 1 (nearest) to the end of the list; words
/// outside the list are far.
class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Word Compass',
    paragraphs: [
      'There is a hidden word. Type any word and the compass tells you how close its meaning is: '
          'the lower the number, the nearer you are. Number 1 is the closest word of all.',
      'Closeness comes from how words are used together in a large collection of text, so "bread" is '
          'near "butter" and "flour", not near "bead". Words far from the hidden word show no number.',
      'Your best guess stays pinned at the top. A hint reveals a word halfway between your best guess and '
          'the target; hints count in your result. Give up to see the word.',
    ],
  );

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  late final CompassPuzzle _puzzle;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'compass-guess');
  late CompassState _state;
  CompassGuess? _last;
  GameResult? _result;
  bool _finishing = false;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = CompassPuzzle.parse(play.record.payload, play.record.reveal);
    _result = play.existingResult();
    _state = _restore();
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  CompassState _restore() {
    final saved = play.loadProgress();
    if (saved == null) return CompassState.initial(_puzzle);
    try {
      return CompassState.fromJson(_puzzle, saved);
    } on FormatException {
      return CompassState.initial(_puzzle);
    }
  }

  bool get _canPlay => _result == null && !_finishing && !_state.isOver;

  void _submit([String? _]) {
    if (!_canPlay) return;
    final word = CompassPuzzle.normalise(_controller.text);
    if (word.isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (!CompassPuzzle.isWord(word)) {
      _reject('One word, letters only');
      return;
    }
    if (_state.contains(word)) {
      _reject('You already tried "$word"');
      return;
    }
    final next = _state.submit(word);
    setState(() {
      _state = next;
      _last = next.guesses.last;
      _controller.clear();
    });
    _focus.requestFocus();
    _persist(next);
  }

  void _hint() {
    if (!_canPlay || !_state.canHint) return;
    final next = _state.hint();
    setState(() {
      _state = next;
      _last = next.guesses.last;
    });
    _persist(next);
  }

  Future<void> _confirmGiveUp() async {
    if (!_canPlay) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give up?'),
        content: const Text('The hidden word is revealed and this puzzle counts as not solved.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep guessing')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reveal the word')),
        ],
      ),
    );
    if (ok != true || !mounted || !_canPlay) return;
    final next = _state.giveUp();
    setState(() => _state = next);
    await _persist(next);
  }

  void _reject(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1500)));
    _focus.requestFocus();
  }

  Future<void> _persist(CompassState state) async {
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
      solved: _state.solved,
      attempts: _state.attempts,
      hints: _state.hints,
      shareLines: _state.shareLines(),
      note: _state.summary(),
      isArchivePlay: play.isArchivePlay,
    );
    await play.complete(context, result, revealTitle: 'The word', reveal: _reveal());
    // Saving the result clears progress; keep the guesses so the review can list them.
    await play.saveProgress(_state.toJson());
    if (mounted) setState(() => _result = result);
  }

  Widget _reveal() => _TargetReveal(puzzle: _puzzle);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: CompassScreen.help,
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
          if (result != null) _finishedHeader(theme, result) else _input(theme),
          Expanded(child: _GuessList(puzzle: _puzzle, state: _state, last: _last, finished: result != null)),
        ],
      ),
    );
  }

  Widget _input(ThemeData theme) {
    final colors = context.gameColors;
    final enabled = _canPlay;
    final last = _last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: enabled,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submit,
                  decoration: const InputDecoration(
                    hintText: 'Type a word',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: enabled ? _submit : null,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
                child: const Text('Guess'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  last == null
                      ? 'Guess ${_state.attempts + 1}. Closer words get lower numbers.'
                      : 'Last: ${_describe(last)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: enabled && _state.canHint ? _hint : null,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(_state.hints == 0 ? 'Hint' : 'Hint (${_state.hints})'),
              ),
              TextButton(
                onPressed: enabled ? _confirmGiveUp : null,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: const Text('Give up'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _describe(CompassGuess g) {
    final band = g.isTarget ? Proximity.found : _puzzle.proximityOf(g.rank);
    final rank = g.rank == null ? '' : ' #${g.rank}';
    final hint = g.isHint ? ' (hint)' : '';
    return '${g.word}$rank · ${band.label}$hint';
  }

  Widget _finishedHeader(ThemeData theme, GameResult result) {
    final colors = context.gameColors;
    final n = result.attempts ?? _state.attempts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Text('THE WORD', style: theme.textTheme.labelSmall),
          Text(_puzzle.target, style: PaperTheme.display(size: 30, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(
            result.solved
                ? 'Solved in $n guess${n == 1 ? '' : 'es'}'
                : 'Not solved · $n guess${n == 1 ? '' : 'es'} before giving up',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => play.showResult(context, result, revealTitle: 'The word', reveal: _reveal()),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            child: const Text('See result'),
          ),
          const SizedBox(height: 8),
          const Rule(),
        ],
      ),
    );
  }
}

/// The best guess pinned above the rest, everything sorted nearest first.
class _GuessList extends StatelessWidget {
  const _GuessList({required this.puzzle, required this.state, required this.last, required this.finished});

  final CompassPuzzle puzzle;
  final CompassState state;
  final CompassGuess? last;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    if (state.guesses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            finished ? 'No guesses were made.' : 'Your guesses appear here, nearest first.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.subtle),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final sorted = state.sorted;
    final best = sorted.first;
    final rest = sorted.sublist(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(finished ? 'YOUR GUESSES' : 'BEST SO FAR', style: theme.textTheme.labelSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: _GuessRow(guess: best, puzzle: puzzle, pinned: true, isLast: best == last),
        ),
        if (rest.isNotEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Rule()),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: rest.length,
            itemBuilder: (context, i) =>
                _GuessRow(guess: rest[i], puzzle: puzzle, pinned: false, isLast: rest[i] == last),
          ),
        ),
      ],
    );
  }
}

/// One guess: the word, a proximity bar, its band and rank. The bar's colour
/// never stands alone; the label and number carry the meaning.
class _GuessRow extends StatelessWidget {
  const _GuessRow({required this.guess, required this.puzzle, required this.pinned, required this.isLast});

  final CompassGuess guess;
  final CompassPuzzle puzzle;
  final bool pinned;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final band = guess.isTarget ? Proximity.found : puzzle.proximityOf(guess.rank);
    final fraction = guess.isTarget ? 1.0 : puzzle.proximityFraction(guess.rank);
    final fill = switch (band) {
      Proximity.found || Proximity.veryClose => colors.correct,
      Proximity.close => colors.misplaced,
      Proximity.warm => colors.absent,
      Proximity.far => colors.absent,
    };
    final rankText = guess.isTarget ? '★' : (guess.rank == null ? '—' : '#${guess.rank}');
    final semantics = guess.isTarget
        ? '${guess.word}, the hidden word'
        : '${guess.word}, ${guess.rank == null ? 'far' : 'rank ${guess.rank}, ${band.label}'}${guess.isHint ? ', hint' : ''}';
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: pinned ? colors.cellHighlight : (isLast ? colors.cellSelected.withValues(alpha: 0.4) : null),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  if (guess.isHint)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lightbulb_outline, size: 14, color: colors.subtle),
                    ),
                  Expanded(
                    child: Text(
                      guess.word,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: pinned ? FontWeight.w700 : FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 6,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(color: colors.cellHighlight, borderRadius: BorderRadius.circular(5)),
                    ),
                    AnimatedContainer(
                      duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
                      height: 10,
                      width: box.maxWidth * fraction,
                      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(5)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: Text(
                '$rankText · ${band.label}',
                style: theme.textTheme.bodySmall?.copyWith(color: band == Proximity.far ? colors.subtle : null),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The target and its three nearest words, for the result screen.
class _TargetReveal extends StatelessWidget {
  const _TargetReveal({required this.puzzle});

  final CompassPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final nearest = [for (var r = 1; r <= 3 && r <= puzzle.vocabularySize; r++) puzzle.wordAt(r)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(puzzle.target, style: PaperTheme.display(size: 36, color: theme.colorScheme.onSurface)),
        if (nearest.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Nearest: ${nearest.join(', ')}', style: theme.textTheme.bodyMedium?.copyWith(color: colors.subtle)),
        ],
      ],
    );
  }
}
