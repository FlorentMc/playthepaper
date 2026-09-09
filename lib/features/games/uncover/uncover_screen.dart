import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/uncover/uncover.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';

/// Uncover: a short factual piece with every word blanked out. Type a word to
/// reveal it wherever it appears, and name the hidden subject to win.
class UncoverScreen extends StatefulWidget {
  const UncoverScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Uncover',
    paragraphs: [
      'A short piece about one subject is hidden behind blocks. Type any word and every place it appears in the '
          'text is uncovered. Small words such as the, of and with are shown from the start.',
      'The subject itself is the thick block, ▇▇▇, wherever the name would be. Those blocks never open by '
          'guessing their own words: you win by typing the name, and sensible variants are accepted.',
      'Three hints wait behind the hint button: what sort of thing it is, the letter it starts with, and one '
          'telling fact. Each hint costs a point.',
      'You start on ten points. A hint costs one, and every five guesses costs one; you keep at least one point '
          'if you get there. Give up to see everything, with nothing scored.',
      'Each piece runs to about 120 words, with sixty or so words to find. Most players get there in twenty to '
          'forty guesses, and the name often comes long before the last block does.',
      'The text field is the whole game on a keyboard: type a word and press Enter. Tab reaches the hint and '
          'give up buttons.',
    ],
  );

  @override
  State<UncoverScreen> createState() => _UncoverScreenState();
}

class _UncoverScreenState extends State<UncoverScreen> {
  late final UncoverPuzzle _puzzle;
  late UncoverState _state;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'uncover-guess');
  final ScrollController _guessScroll = ScrollController();
  GameResult? _result;
  bool _finishing = false;

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = UncoverPuzzle.parse(_play.record.payload, _play.record.reveal);
    _result = _play.existingResult();
    _state = _restore();
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _guessScroll.dispose();
    super.dispose();
  }

  UncoverState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return UncoverState.initial(_puzzle);
    try {
      return UncoverState.fromJson(_puzzle, saved);
    } on FormatException {
      return UncoverState.initial(_puzzle);
    }
  }

  bool get _canPlay => _result == null && !_finishing && _state.isPlaying;

  void _guess([String? _]) {
    if (!_canPlay) return;
    final raw = _controller.text;
    switch (_state.check(raw)) {
      case UncoverCheck.empty:
        _focus.requestFocus();
        return;
      case UncoverCheck.common:
        _say('That word is shown already');
        return;
      case UncoverCheck.repeat:
        _say('You have tried that word');
        return;
      case UncoverCheck.ok:
        break;
    }
    final next = _state.submit(raw);
    setState(() {
      _state = next;
      _controller.clear();
    });
    _focus.requestFocus();
    _showLatestGuess();
    _persist(next);
  }

  /// Brings the newest guess back into view when the player has scrolled the
  /// strip along.
  void _showLatestGuess() {
    if (!_guessScroll.hasClients || _guessScroll.offset == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _guessScroll.jumpTo(0);
    } else {
      _guessScroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _hint() {
    if (!_canPlay || !_state.canHint) return;
    final next = _state.useHint();
    setState(() => _state = next);
    _persist(next);
  }

  Future<void> _confirmGiveUp() async {
    if (!_canPlay) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give up?'),
        content: const Text('The whole text and the subject are shown, and this puzzle counts as not solved.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Show it all')),
        ],
      ),
    );
    if (ok != true || !mounted || !_canPlay) return;
    final next = _state.giveUp();
    setState(() => _state = next);
    await _persist(next);
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1500)));
    _focus.requestFocus();
  }

  Future<void> _persist(UncoverState state) async {
    await _play.saveProgress(state.toJson());
    if (!mounted || !state.isOver) return;
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing || _result != null) return;
    _finishing = true;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.isSolved,
      attempts: _state.guessCount,
      hints: _state.hintsUsed,
      points: _state.points,
      maxPoints: UncoverState.maxPoints,
      shareLines: _state.shareLines(),
      note: _state.summary(),
      isArchivePlay: _play.isArchivePlay,
    );
    await _play.complete(context, result, revealTitle: 'The subject', reveal: _reveal());
    // Saving the result clears progress; keep it so the review still has the guesses.
    await _play.saveProgress(_state.toJson());
    if (mounted) setState(() => _result = result);
  }

  Widget _reveal() => _SubjectReveal(puzzle: _puzzle, sources: _play.record.sources);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: UncoverScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_play.challenge != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text('Friend: ${_play.challenge!.summary()}', style: theme.textTheme.labelMedium),
            ),
          if (result != null) _finishedHeader(theme, result) else _counters(theme),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _StoryText(state: _state),
                if (_state.revealedHints.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final (i, hint) in _state.revealedHints.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 18, color: context.gameColors.subtle),
                          const SizedBox(width: 6),
                          Expanded(child: Text('Hint ${i + 1}: $hint', style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
                if (_state.isOver && _play.record.sources.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('SOURCES', style: theme.textTheme.labelSmall),
                  for (final source in _play.record.sources) _SourceTile(source: source),
                ],
              ],
            ),
          ),
          if (result == null) ...[
            _GuessStrip(state: _state, controller: _guessScroll),
            _input(theme),
          ],
        ],
      ),
    );
  }

  Widget _counters(ThemeData theme) {
    final colors = context.gameColors;
    final last = _state.lastGuess;
    final feedback = last == null
        ? 'Type a word to uncover it wherever it appears.'
        : _state.isSolved
            ? 'That is the subject. Well done.'
            : last.matches == 0
                ? '“${last.word}” is not in the text.'
                : '“${last.word}” appears ${last.matches} time${last.matches == 1 ? '' : 's'}.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_state.revealedCount} of ${_state.hiddenCount} words uncovered · '
            '${_state.guessCount} guess${_state.guessCount == 1 ? '' : 'es'}'
            '${_state.hintsUsed == 0 ? '' : ' · ${_state.hintsUsed} hint${_state.hintsUsed == 1 ? '' : 's'}'}',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          Text(feedback, style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle)),
        ],
      ),
    );
  }

  Widget _input(ThemeData theme) {
    final enabled = _canPlay;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('uncover-field'),
                  controller: _controller,
                  focusNode: _focus,
                  enabled: enabled,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _guess,
                  decoration: const InputDecoration(
                    hintText: 'Type a word, or the subject',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('uncover-guess'),
                onPressed: enabled ? _guess : null,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 48)),
                child: const Text('Guess'),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('uncover-hint'),
                    onPressed: enabled && _state.canHint ? _hint : null,
                    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                    label: Text('Hint (${_puzzle.hints.length - _state.hintsUsed})', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('uncover-give-up'),
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

  Widget _finishedHeader(ThemeData theme, GameResult result) {
    final colors = context.gameColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Text('THE SUBJECT', style: theme.textTheme.labelSmall),
          Text(_puzzle.subject, style: PaperTheme.display(size: 26, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(result.summary(), style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle)),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('uncover-see-result'),
            onPressed: () => _play.showResult(context, result, revealTitle: 'The subject', reveal: _reveal()),
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

/// The text itself: uncovered words as words, everything else as blocks.
/// The subject's own words are the short thick blocks and stay shut until
/// the puzzle ends.
class _StoryText extends StatelessWidget {
  const _StoryText({required this.state});

  final UncoverState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final base = theme.textTheme.bodyLarge!.copyWith(height: 1.6);
    final words = state.puzzle.words;
    return Text.rich(
      key: const ValueKey('uncover-text'),
      TextSpan(
        children: [
          for (var i = 0; i < words.length; i++) _span(words[i], i, base, colors),
        ],
      ),
      style: base,
    );
  }

  InlineSpan _span(UncoverWord word, int index, TextStyle base, GameColors colors) {
    if (word.isSeparator) return TextSpan(text: word.text);
    final shown = state.isRevealed(index);
    if (!shown) {
      final subject = word.isSubject;
      return TextSpan(
        text: subject ? UncoverText.mask : '▇' * word.text.length,
        semanticsLabel: subject ? 'the hidden name' : 'a hidden word',
        style: base.copyWith(
          color: subject ? colors.misplaced : colors.absent,
          decoration: subject ? TextDecoration.underline : null,
          decorationColor: colors.misplaced,
        ),
      );
    }
    if (word.isSubject) {
      return TextSpan(
        text: word.text,
        semanticsLabel: 'the subject, ${word.text}',
        style: base.copyWith(color: colors.onFeedback, backgroundColor: colors.correct, fontWeight: FontWeight.w700),
      );
    }
    if (state.isLatest(index)) {
      return TextSpan(
        text: word.text,
        semanticsLabel: 'just uncovered, ${word.text}',
        style: base.copyWith(backgroundColor: colors.cellSelected, fontWeight: FontWeight.w600),
      );
    }
    return TextSpan(text: word.text);
  }
}

/// The guesses so far, newest first, each with the number of words it opened.
class _GuessStrip extends StatelessWidget {
  const _GuessStrip({required this.state, required this.controller});

  final UncoverState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    if (state.guesses.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final guesses = state.guesses.reversed.toList(growable: false);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: guesses.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final guess = guesses[index];
          final found = guess.matches > 0;
          return Semantics(
            label: found
                ? '${guess.word}, ${guess.matches} found'
                : '${guess.word}, not in the text',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: found ? colors.cellHighlight : colors.cell,
                border: Border.all(color: colors.cellBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(found ? Icons.check : Icons.remove, size: 14, color: found ? colors.correct : colors.subtle),
                  const SizedBox(width: 4),
                  Text('${guess.word} ${guess.matches}', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The reveal shown on the result screen: the subject and the whole piece.
class _SubjectReveal extends StatelessWidget {
  const _SubjectReveal({required this.puzzle, required this.sources});

  final UncoverPuzzle puzzle;
  final List<SourceRef> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(puzzle.subject, style: PaperTheme.display(size: 24, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text(puzzle.text, style: theme.textTheme.bodyMedium),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('SOURCES', style: theme.textTheme.labelSmall),
          for (final source in sources) _SourceTile(source: source),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final SourceRef source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
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
