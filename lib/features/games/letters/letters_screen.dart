import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/letters/letters.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'letters_answer_list.dart';
import 'letters_honeycomb.dart';
import 'letters_rank_bar.dart';

/// Bee-style Letters: seven letters, one compulsory centre, find the words.
class LettersScreen extends StatefulWidget {
  const LettersScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Letters',
    paragraphs: [
      'Make words of four letters or more from the seven letters. Every word must use the centre '
          'letter, and a letter can be used as often as you like.',
      'Four-letter words score 1 point; longer words score one point per letter. A pangram uses all '
          'seven letters and earns 7 extra points.',
      'Your rank rises with your points: Beginner, Good start, Moving up, Good, Solid, Nice, Great, '
          'Amazing, then Genius at 70% of the maximum.',
      'Tap the letters or type on a keyboard. Enter submits, Backspace deletes, and Shuffle '
          'rearranges the outer letters.',
      'Words are checked against today\'s fixed list. Tap Finish when you are done: it locks the '
          'puzzle and reveals every word.',
    ],
  );

  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

enum _FeedbackKind { accepted, rejected }

class _LettersScreenState extends State<LettersScreen> {
  late final LettersPuzzle _puzzle;
  late LettersState _state;
  late List<String> _outer;
  GameResult? _existing;
  String _word = '';
  String? _feedback;
  _FeedbackKind _feedbackKind = _FeedbackKind.rejected;
  Timer? _feedbackTimer;
  bool _completing = false;
  final FocusNode _focus = FocusNode(debugLabel: 'letters');

  static const int _maxWordLength = 20;

  PlayContext get play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = LettersPuzzle.parse(play.record.payload, play.record.reveal);
    final progress = play.loadProgress();
    _state = progress == null ? LettersState(puzzle: _puzzle) : LettersState.fromJson(_puzzle, progress);
    _outer = _restoreOuter(progress?['outer']);
    _existing = play.existingResult();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  List<String> _restoreOuter(Object? saved) {
    final base = _puzzle.outer.split('');
    if (saved is String && saved.length == base.length && saved.split('').toSet().containsAll(base)) {
      return saved.split('');
    }
    return base;
  }

  bool get _canPlay => _existing == null && !_state.isFinished && !_completing;

  Map<String, dynamic> _progressJson() => {..._state.toJson(), 'outer': _outer.join()};

  void _append(String letter) {
    if (!_canPlay || _word.length >= _maxWordLength) return;
    setState(() => _word += letter);
  }

  void _delete() {
    if (!_canPlay || _word.isEmpty) return;
    setState(() => _word = _word.substring(0, _word.length - 1));
  }

  void _shuffle() {
    if (!_canPlay) return;
    setState(() => _outer = List.of(_outer)..shuffle());
    play.saveProgress(_progressJson());
  }

  void _submit() {
    if (!_canPlay) return;
    final outcome = _state.submit(_word);
    setState(() {
      _word = '';
      switch (outcome) {
        case SubmitTooShort():
          _showFeedback('Too short', _FeedbackKind.rejected);
        case SubmitMissingCenter():
          _showFeedback('Missing centre letter', _FeedbackKind.rejected);
        case SubmitBadLetters():
          _showFeedback('Not in the letters', _FeedbackKind.rejected);
        case SubmitNotInList():
          _showFeedback("Not in today's list", _FeedbackKind.rejected);
        case SubmitAlreadyFound():
          _showFeedback('Already found', _FeedbackKind.rejected);
        case SubmitAccepted(:final points, :final isPangram, :final state):
          _state = state;
          _showFeedback('+$points ${isPangram ? 'Pangram!' : _praise(points)}', _FeedbackKind.accepted);
      }
    });
    if (outcome is SubmitAccepted) play.saveProgress(_progressJson());
  }

  String _praise(int points) => points == 1
      ? 'Good'
      : points < 7
      ? 'Nice!'
      : 'Awesome!';

  void _showFeedback(String text, _FeedbackKind kind) {
    _feedback = text;
    _feedbackKind = kind;
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_canPlay || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    final ch = event.character ?? key.keyLabel;
    if (ch.length == 1 && RegExp(r'[A-Za-z]').hasMatch(ch)) {
      _append(ch.toUpperCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirmFinish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish the puzzle?'),
        content: Text(
          'Finishing locks this puzzle and reveals every word in the list. '
          'You keep your ${_state.points} point${_state.points == 1 ? '' : 's'} at ${_state.rank.label}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Finish')),
        ],
      ),
    );
    if (ok == true && mounted) await _finish();
  }

  Future<void> _finish() async {
    if (!_canPlay) return;
    _completing = true;
    _feedbackTimer?.cancel();
    final finished = _state.finish();
    setState(() {
      _state = finished;
      _word = '';
      _feedback = null;
    });
    final result = GameResult(
      puzzleId: play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: finished.rank == LettersRank.genius,
      points: finished.points,
      maxPoints: _puzzle.maxScore,
      shareLines: ['${finished.rank.label} · ${finished.found.length}/${_puzzle.answers.length} words'],
      isArchivePlay: play.isArchivePlay,
    );
    await play.complete(context, result, revealTitle: 'Every word', reveal: _reveal());
    // Saving the result clears progress; keep the found list so the finished board can mark it.
    await play.saveProgress(_progressJson());
    if (mounted) setState(() => _existing = result);
  }

  Widget _reveal() => LettersAnswerList(puzzle: _puzzle, found: _state.found.toSet());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = _existing;
    final friendPoints = play.challenge?.points;
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: LettersScreen.help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTap: _focus.requestFocus,
          behavior: HitTestBehavior.translucent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  LettersRankBar(points: existing?.points ?? _state.points, maxScore: _puzzle.maxScore),
                  if (friendPoints != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Friend: $friendPoints point${friendPoints == 1 ? '' : 's'}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (existing != null) ..._finishedBody(theme, existing) else ..._playingBody(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _playingBody(ThemeData theme) {
    final colors = context.gameColors;
    final found = _state.foundSorted;
    return [
      _WordDisplay(word: _word, puzzle: _puzzle),
      const SizedBox(height: 8),
      _FeedbackLine(text: _feedback, accepted: _feedbackKind == _FeedbackKind.accepted),
      const SizedBox(height: 8),
      LettersHoneycomb(center: _puzzle.center, outer: _outer, onLetter: _canPlay ? _append : null),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(onPressed: _canPlay ? _delete : null, child: const Text('Delete')),
          const SizedBox(width: 12),
          IconButton.outlined(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Shuffle',
            onPressed: _canPlay ? _shuffle : null,
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: _canPlay ? _submit : null, child: const Text('Enter')),
        ],
      ),
      const SizedBox(height: 24),
      const Rule(),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              found.isEmpty
                  ? 'No words yet'
                  : 'You have found ${found.length} word${found.length == 1 ? '' : 's'}'
                        '${_state.pangramsFound > 0 ? ' · ${_state.pangramsFound} pangram${_state.pangramsFound == 1 ? '' : 's'}' : ''}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          OutlinedButton(onPressed: _canPlay ? _confirmFinish : null, child: const Text('Finish')),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final word in found)
            _FoundChip(word: word, pangram: _puzzle.isPangramWord(word), ink: theme.colorScheme.onSurface),
        ],
      ),
      if (found.isEmpty)
        Text(
          'Words of ${_puzzle.minLength}+ letters using ${_puzzle.center} appear here.',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.subtle),
        ),
    ];
  }

  List<Widget> _finishedBody(ThemeData theme, GameResult result) {
    return [
      Text('Finished · the board is locked', style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      LettersHoneycomb(center: _puzzle.center, outer: _outer, onLetter: null),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => play.showResult(context, result, revealTitle: 'Every word', reveal: _reveal()),
        child: const Text('See result'),
      ),
      const SizedBox(height: 24),
      const Rule(),
      const SizedBox(height: 12),
      Text('EVERY WORD', style: theme.textTheme.labelSmall),
      const SizedBox(height: 8),
      _reveal(),
    ];
  }
}

class _WordDisplay extends StatelessWidget {
  const _WordDisplay({required this.word, required this.puzzle});

  final String word;
  final LettersPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final base = DaypencilTheme.display(size: 30, color: theme.colorScheme.onSurface);
    return Semantics(
      label: word.isEmpty ? 'No letters typed' : 'Current word ${word.split('').join(' ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 44,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: word.isEmpty
                  ? Text(
                      'Tap letters or type',
                      style: DaypencilTheme.display(size: 20, weight: 400, color: colors.subtle),
                    )
                  : Text.rich(
                      TextSpan(
                        style: base.copyWith(letterSpacing: 2),
                        children: [
                          for (final ch in word.split(''))
                            TextSpan(
                              text: ch,
                              style: ch == puzzle.center
                                  ? TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold)
                                  : puzzle.letters.contains(ch)
                                  ? null
                                  : TextStyle(color: colors.subtle),
                            ),
                          TextSpan(
                            text: '|',
                            style: TextStyle(color: colors.subtle, fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.text, required this.accepted});

  final String? text;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: 24,
      child: Center(
        child: AnimatedSwitcher(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          child: text == null
              ? const SizedBox.shrink()
              : Semantics(
                  liveRegion: true,
                  child: Text(
                    text!,
                    key: ValueKey(text),
                    style: DaypencilTheme.body(size: 16, weight: 600, color: accepted ? colors.correct : colors.error),
                  ),
                ),
        ),
      ),
    );
  }
}

class _FoundChip extends StatelessWidget {
  const _FoundChip({required this.word, required this.pangram, required this.ink});

  final String word;
  final bool pangram;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: pangram ? '$word, pangram' : word,
      child: ExcludeSemantics(
        child: Chip(
          label: Text(
            pangram ? '★ $word' : word,
            style: DaypencilTheme.body(size: 14, weight: pangram ? 700 : 400, color: ink),
          ),
        ),
      ),
    );
  }
}
