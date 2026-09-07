import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/crossword/crossword_puzzle.dart';
import '../../../engines/crossword/crossword_state.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../shared/widgets/letter_keyboard.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'crossword_grid.dart';

const String _storiesTitle = "From today's stories";
const String _seededSuffix = ", from today's stories";

class CrosswordScreen extends StatefulWidget {
  const CrosswordScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Mini Crossword',
    paragraphs: [
      'Fill the 5×5 grid from the clues. Tap a cell to select it and read its clue; tap the same cell again, '
          'or tap the clue bar, to switch between Across and Down. Typing moves you along the entry.',
      'The ‹ and › buttons step through the clues. On a keyboard, the arrows move around the grid, '
          'Tab jumps to the next clue and Space switches direction.',
      'The ⋮ menu can check a cell, a word or the whole puzzle, marking wrong letters with a slash, '
          'or reveal them. Each check or reveal counts as a hint in your result.',
      'Your time is recorded but only shown if you turn on timers in Settings. The puzzle is complete '
          'when every letter is right.',
    ],
  );

  @override
  State<CrosswordScreen> createState() => _CrosswordScreenState();
}

class _CrosswordScreenState extends State<CrosswordScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final CrosswordPuzzle _puzzle;
  late CrosswordState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = CrosswordPuzzle.parse(_play.record.payload, _play.record.reveal);
    _result = _play.existingResult();
    _state = _result != null ? CrosswordState.solved(_puzzle) : _restore();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  CrosswordState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return CrosswordState.initial(_puzzle);
    try {
      return CrosswordState.fromJson(_puzzle, saved);
    } on FormatException {
      return CrosswordState.initial(_puzzle);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _save();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else {
      _stopTimer();
      _save();
    }
  }

  bool get _playing => _result == null && !_completing;

  void _startTimer() {
    if (!_playing || _timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_playing) return;
      setState(() => _state = _state.tick());
      if (++_ticksSinceSave >= _ticksPerSave) _save();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _save() {
    if (!_playing) return;
    _ticksSinceSave = 0;
    _play.saveProgress(_state.toJson());
  }

  void _apply(CrosswordState next, {bool persist = true}) {
    if (!_playing || identical(next, _state)) return;
    setState(() => _state = next);
    if (persist) _save();
    if (next.isSolved) _complete();
  }

  Future<void> _complete() async {
    if (!_playing) return;
    _completing = true;
    _stopTimer();
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: true,
      seconds: _state.elapsedSeconds,
      hints: _state.hints,
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: _revealTitle, reveal: _reveal());
  }

  String? get _revealTitle => _puzzle.seeded.isEmpty ? null : _storiesTitle;

  Widget? _reveal() => _puzzle.seeded.isEmpty ? null : _StoriesReveal(puzzle: _puzzle, play: _play);

  void _tapCell(int cell) {
    if (cell == _state.selected) {
      _apply(_state.toggleDirection(), persist: false);
    } else {
      _apply(_state.select(cell), persist: false);
    }
  }

  void _onArrow(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return _apply(_state.move(Arrow.up), persist: false);
    if (key == LogicalKeyboardKey.arrowDown) return _apply(_state.move(Arrow.down), persist: false);
    if (key == LogicalKeyboardKey.arrowLeft) return _apply(_state.move(Arrow.left), persist: false);
    if (key == LogicalKeyboardKey.arrowRight) return _apply(_state.move(Arrow.right), persist: false);
    if (key == LogicalKeyboardKey.tab) return _apply(_state.nextClue(), persist: false);
    if (key == LogicalKeyboardKey.space) return _apply(_state.toggleDirection(), persist: false);
  }

  Future<void> _menu(String action) async {
    if (!_playing) return;
    switch (action) {
      case 'check-cell':
        _apply(_state.checkCell());
      case 'check-word':
        _apply(_state.checkWord());
      case 'check-puzzle':
        _apply(_state.checkPuzzle());
      case 'reveal-cell':
        _apply(_state.revealCell());
      case 'reveal-word':
        _apply(_state.revealWord());
      case 'reveal-puzzle':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reveal the whole puzzle?'),
            content: const Text('Every cell is filled in and this counts as a hint.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reveal')),
            ],
          ),
        );
        if (confirmed == true && mounted) _apply(_state.revealPuzzle());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final result = _result;
    final done = result != null;
    final entry = _state.currentEntry;

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      help: CrosswordScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      actions: [
        if (!done)
          PopupMenuButton<String>(
            tooltip: 'Check or reveal',
            icon: const Icon(Icons.rule),
            onSelected: _menu,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'check-cell', child: Text('Check cell')),
              PopupMenuItem(value: 'check-word', child: Text('Check word')),
              PopupMenuItem(value: 'check-puzzle', child: Text('Check puzzle')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'reveal-cell', child: Text('Reveal cell')),
              PopupMenuItem(value: 'reveal-word', child: Text('Reveal word')),
              PopupMenuItem(value: 'reveal-puzzle', child: Text('Reveal puzzle')),
              PopupMenuDivider(),
              PopupMenuItem(enabled: false, child: Text('Each counts as a hint')),
            ],
          ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final teaser = _puzzle.teaser;
          final grid = Column(
            children: [
              if (teaser != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.newspaper, size: 14, color: colors.subtle),
                      const SizedBox(width: 6),
                      Expanded(child: Text('$_storiesTitle · $teaser', style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: CrosswordGrid(state: _state, onTap: _tapCell, enabled: !done),
                  ),
                ),
              ),
            ],
          );
          final info = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (_play.challenge != null)
                  Expanded(child: Text('Friend: ${_play.challenge!.summary()}', style: theme.textTheme.bodySmall))
                else
                  const Spacer(),
                if (settings.showTimers && !done)
                  Text(GameResult.formatSeconds(_state.elapsedSeconds), style: theme.textTheme.labelMedium),
                if (_state.hints > 0 && !done)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text('${_state.hints} hint${_state.hints == 1 ? '' : 's'}', style: theme.textTheme.labelMedium),
                  ),
              ],
            ),
          );
          final clues = _ClueLists(
            puzzle: _puzzle,
            state: _state,
            wide: wide,
            onSelect: (e) => _apply(_state.selectEntry(e), persist: false),
          );

          if (done) {
            return ListView(
              children: [
                info,
                grid,
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Column(
                    children: [
                      Text(result.summary(), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _play.showResult(context, result, revealTitle: _revealTitle, reveal: _reveal()),
                        child: const Text('See result'),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 320, child: clues),
              ],
            );
          }

          final board = Column(
            children: [
              info,
              grid,
              _ClueBar(
                entry: entry,
                onPrev: () => _apply(_state.prevClue(), persist: false),
                onNext: () => _apply(_state.nextClue(), persist: false),
                onToggle: () => _apply(_state.toggleDirection(), persist: false),
                colors: colors,
              ),
            ],
          );

          return Column(
            children: [
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          Expanded(flex: 5, child: SingleChildScrollView(child: board)),
                          Expanded(flex: 4, child: clues),
                        ],
                      )
                    : Column(
                        children: [
                          board,
                          Expanded(child: clues),
                        ],
                      ),
              ),
              LetterKeyboard(
                onLetter: (ch) => _apply(_state.type(ch)),
                onBackspace: () => _apply(_state.backspace()),
                onArrow: _onArrow,
                showEnter: false,
                enabled: !done,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClueBar extends StatelessWidget {
  const _ClueBar({
    required this.entry,
    required this.onPrev,
    required this.onNext,
    required this.onToggle,
    required this.colors,
  });

  final CrosswordEntry entry;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final GameColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(color: colors.cellSelected, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous clue', onPressed: onPrev),
          Expanded(
            child: Semantics(
              button: true,
              label: '${entry.label}: ${entry.clue}${entry.isSeeded ? _seededSuffix : ''}. Switch direction',
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${entry.label} · ', style: theme.textTheme.labelMedium),
                      TextSpan(text: entry.clue, style: theme.textTheme.bodyMedium),
                      if (entry.isSeeded) _seededGlyph(theme),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next clue', onPressed: onNext),
        ],
      ),
    );
  }
}

class _ClueLists extends StatelessWidget {
  const _ClueLists({required this.puzzle, required this.state, required this.wide, required this.onSelect});

  final CrosswordPuzzle puzzle;
  final CrosswordState state;
  final bool wide;
  final void Function(CrosswordEntry) onSelect;

  @override
  Widget build(BuildContext context) {
    final across = _ClueColumn(title: 'Across', entries: puzzle.across, state: state, onSelect: onSelect);
    final down = _ClueColumn(title: 'Down', entries: puzzle.down, state: state, onSelect: onSelect);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: across), Expanded(child: down)],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [across, down],
    );
  }
}

class _ClueColumn extends StatelessWidget {
  const _ClueColumn({required this.title, required this.entries, required this.state, required this.onSelect});

  final String title;
  final List<CrosswordEntry> entries;
  final CrosswordState state;
  final void Function(CrosswordEntry) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final current = state.currentEntry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
          child: Text(title.toUpperCase(), style: theme.textTheme.labelSmall),
        ),
        for (final e in entries)
          Semantics(
            button: true,
            selected: e == current,
            label: '${e.label}, ${e.clue}${e.isSeeded ? _seededSuffix : ''}${state.isEntryFull(e) ? ', filled' : ''}',
            child: InkWell(
              onTap: () => onSelect(e),
              child: Container(
                color: e == current ? colors.cellHighlight : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 24, child: Text('${e.number}', style: theme.textTheme.labelMedium)),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: e.clue),
                          if (e.isSeeded) _seededGlyph(theme),
                        ]),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: state.isEntryFull(e) ? colors.subtle : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The newspaper mark after a seeded clue. Silent to screen readers; the
/// clue's semantics label carries the suffix instead.
WidgetSpan _seededGlyph(ThemeData theme) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.newspaper, size: 14, color: theme.colorScheme.onSurface),
      ),
    );

/// The result screen's explanation: which entries came from the news, the
/// sentence each answer appeared in, and a link to the story.
class _StoriesReveal extends StatelessWidget {
  const _StoriesReveal({required this.puzzle, required this.play});

  final CrosswordPuzzle puzzle;
  final PlayContext play;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in puzzle.seeded) ...[
          _SeededEntry(
            seed: s,
            answer: puzzle.answerOf(puzzle.entryLabelled(s.label)!),
            story: play.storyById(s.storyId),
          ),
          if (s != puzzle.seeded.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SeededEntry extends StatelessWidget {
  const _SeededEntry({required this.seed, required this.answer, required this.story});

  final CrosswordSeedReveal seed;
  final String answer;
  final Story? story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bold = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in RegExp('\\b$answer\\b', caseSensitive: false).allMatches(seed.excerpt)) {
      if (m.start > at) spans.add(TextSpan(text: seed.excerpt.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(0), style: bold));
      at = m.end;
    }
    if (at < seed.excerpt.length) spans.add(TextSpan(text: seed.excerpt.substring(at)));
    final story = this.story;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${seed.label} · $answer', style: bold),
        const SizedBox(height: 2),
        Text.rich(TextSpan(children: spans), style: theme.textTheme.bodyMedium),
        if (story != null)
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('${story.publisher} · Read the story'),
            onPressed: () => launchUrl(Uri.parse(story.url), mode: LaunchMode.externalApplication),
          ),
      ],
    );
  }
}
