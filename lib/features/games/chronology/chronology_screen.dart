import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/chronology/chronology.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'chronology_card.dart';

/// Before & After: four events from one theme, shuffled; put them in the
/// order they happened.
class ChronologyScreen extends StatefulWidget {
  const ChronologyScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Before & After',
    paragraphs: [
      'Four events from one theme are shown out of order. Put them in the order they happened, with the earliest at the top.',
      'Drag a card by its handle, or hold a card and drag it, or use the up and down arrows on each card. You can also tap a card '
          'to pick it up and tap another to move it there. Undo takes back your last move.',
      'A hint puts the earliest event that is out of place where it belongs and locks it there. Each hint is counted in your result.',
      'Press Submit when you are happy. You score a point for each event in the right position, then see the verified order with '
          'every year, a short explanation and the sources.',
      'On a keyboard, the up and down arrows move between cards, Space or Enter picks a card up and drops it, and the arrows carry '
          'a picked-up card. Tab reaches the buttons.',
      'Most sets run across two centuries or more, with at least one pair close enough together to make you think.',
    ],
  );

  @override
  State<ChronologyScreen> createState() => _ChronologyScreenState();
}

class _ChronologyScreenState extends State<ChronologyScreen> {
  late final ChronologyPuzzle _puzzle;
  late ChronologyState _state;
  GameResult? _result;
  bool _completing = false;
  int _cursor = 0;
  bool _picked = false;
  bool _keyboardUsed = false;
  final FocusNode _focus = FocusNode(debugLabel: 'chronology');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = ChronologyPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    if (_result == null && _state.submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
  }

  ChronologyState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return ChronologyState.initial(_puzzle);
    try {
      return ChronologyState.fromJson(_puzzle, saved);
    } on FormatException {
      return ChronologyState.initial(_puzzle);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _playing => _result == null && !_completing && !_state.submitted;

  void _apply(ChronologyState next) {
    if (!_playing || identical(next, _state)) return;
    setState(() => _state = next);
    _play.saveProgress(next.toJson());
  }

  void _move(int from, int to) {
    final next = _state.move(from, to);
    if (identical(next, _state)) return;
    _cursor = to;
    _apply(next);
  }

  void _tapCard(int index) {
    _focus.requestFocus();
    if (_state.isLocked(index)) return;
    if (_picked && index != _cursor) {
      _move(_cursor, index);
      setState(() => _picked = false);
      return;
    }
    setState(() {
      _cursor = index;
      _picked = !_picked;
    });
  }

  void _undo() {
    setState(() => _picked = false);
    _apply(_state.undo());
  }

  Future<void> _hint() async {
    if (!_playing || !_state.canHint) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Place the next event?'),
        content: const Text('The earliest event that is out of place moves to where it belongs. Counts as a hint.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Place')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _picked = false);
    _apply(_state.hint());
  }

  Future<void> _submit() async {
    if (!_playing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit this order?'),
        content: const Text('You score a point for each event in the right place.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_playing) return;
    final next = _state.submit();
    setState(() {
      _state = next;
      _picked = false;
    });
    await _play.saveProgress(next.toJson());
    if (!mounted) return;
    await _complete();
  }

  Future<void> _complete() async {
    if (_completing || _result != null) return;
    _completing = true;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.isSolved,
      points: _state.points,
      maxPoints: ChronologyPuzzle.eventCount,
      hints: _state.hints,
      shareLines: _state.shareLines(),
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: 'The order', reveal: _RevealSummary(puzzle: _puzzle));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing || !_focus.hasPrimaryFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final int delta;
    if (key == LogicalKeyboardKey.arrowUp) {
      delta = -1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      delta = 1;
    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _keyboardUsed = true;
      _tapCard(_cursor);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      setState(() => _picked = false);
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    _keyboardUsed = true;
    final target = (_cursor + delta).clamp(0, _state.length - 1);
    if (_picked) {
      _move(_cursor, target);
      setState(() {});
    } else {
      setState(() => _cursor = target);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null || _state.submitted;
    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: ChronologyScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_puzzle.title != null)
                    Text(_puzzle.title!, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    done ? 'The verified order, earliest first.' : 'Put these in the order they happened, earliest at the top.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: done
                  ? _RevealList(
                      puzzle: _puzzle,
                      playerOrder: _state.submitted ? _state.order : null,
                      sources: _play.record.sources,
                      explanation: _puzzle.explanation,
                    )
                  : _buildList(context),
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  children: [
                    Text(result.summary(), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => _play.showResult(
                        context,
                        result,
                        revealTitle: 'The order',
                        reveal: _RevealSummary(puzzle: _puzzle),
                      ),
                      child: const Text('See result'),
                    ),
                  ],
                ),
              ),
            if (!done) _buildControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final showCursor = _keyboardUsed || _picked;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      physics: const ClampingScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _state.length,
      onReorder: (from, to) {
        setState(() => _picked = false);
        _move(from, to > from ? to - 1 : to);
      },
      itemBuilder: (context, index) {
        final id = _state.order[index];
        final locked = _state.isLocked(index);
        final card = ChronologyCard(
          index: index,
          count: _state.length,
          text: _puzzle.eventById(id).text,
          locked: locked,
          focused: showCursor && _cursor == index,
          picked: _picked && _cursor == index,
          onTap: locked ? null : () => _tapCard(index),
          onUp: _state.canMove(index, index - 1) ? () => _move(index, index - 1) : null,
          onDown: _state.canMove(index, index + 1) ? () => _move(index, index + 1) : null,
          dragHandle: locked
              ? null
              : ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: 'Drag handle',
                    excludeSemantics: true,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.drag_handle, color: context.gameColors.subtle),
                    ),
                  ),
                ),
        );
        return Padding(
          key: ValueKey('chronology-card-$id'),
          padding: const EdgeInsets.only(bottom: 8),
          child: locked ? card : ReorderableDelayedDragStartListener(index: index, child: card),
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('chronology-undo'),
              onPressed: _state.canUndo ? _undo : null,
              icon: const Icon(Icons.undo, size: 20),
              label: const Text('Undo'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('chronology-hint'),
              onPressed: _state.canHint ? _hint : null,
              icon: const Icon(Icons.lightbulb_outline, size: 20),
              label: const Text('Hint'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('chronology-submit'),
              onPressed: _submit,
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The verified order after play: year, event, how the player placed it,
/// then the explanation and the sources.
class _RevealList extends StatelessWidget {
  const _RevealList({
    required this.puzzle,
    required this.playerOrder,
    required this.sources,
    required this.explanation,
  });

  final ChronologyPuzzle puzzle;

  /// The submitted arrangement, when this session still has it.
  final List<String>? playerOrder;
  final List<SourceRef> sources;
  final String explanation;

  static String ordinal(int position) => switch (position) {
        1 => '1st',
        2 => '2nd',
        3 => '3rd',
        _ => '${position}th',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final order = puzzle.order;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (var i = 0; i < order.length; i++) ...[
          Builder(
            builder: (context) {
              final id = order[i];
              final had = playerOrder?.indexOf(id);
              final right = had == i;
              final verdict = had == null
                  ? null
                  : right
                      ? 'You had this here'
                      : 'You had this ${ordinal(had + 1)}';
              return Semantics(
                key: ValueKey('chronology-reveal-$id'),
                label: [
                  '${ordinal(i + 1)}, ${puzzle.dates[id]}',
                  puzzle.eventById(id).text,
                  ?verdict,
                ].join(', '),
                excludeSemantics: true,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(puzzle.dates[id]!, style: PaperTheme.display(size: 20, color: theme.colorScheme.onSurface)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(puzzle.eventById(id).text, style: theme.textTheme.bodyLarge),
                              if (verdict != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(right ? Icons.check : Icons.close, size: 16, color: right ? colors.correct : colors.error),
                                      const SizedBox(width: 4),
                                      Text(verdict, style: theme.textTheme.labelSmall),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Text(explanation, style: theme.textTheme.bodyMedium),
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

/// The compact reveal on the result screen: each year and event, then the explanation.
class _RevealSummary extends StatelessWidget {
  const _RevealSummary({required this.puzzle});

  final ChronologyPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final id in puzzle.order)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 64, child: Text(puzzle.dates[id]!, style: PaperTheme.body(weight: 700))),
                Expanded(child: Text(puzzle.eventById(id).text, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(puzzle.explanation, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
