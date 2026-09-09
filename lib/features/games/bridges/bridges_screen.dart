import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/bridges/bridges.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'bridges_board.dart';

/// Bridges: join numbered islands with straight bridges into one network.
class BridgesScreen extends StatefulWidget {
  const BridgesScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Bridges',
    paragraphs: [
      'Every circle is an island, and its number says how many bridges must reach it. Bridges run straight '
          'across or straight down, never diagonally, and never cross one another. Two islands may share at most '
          'two bridges.',
      'The puzzle is solved when every island has its number and you can walk from any island to any other. '
          'Every puzzle has exactly one answer.',
      'Tap an island, then an island in line with it, to draw a bridge. Tap that second island again to make the '
          'bridge double, and once more to remove it. Tap the selected island, or the water, to clear the selection. '
          'A tick marks an island that has its bridges; a cross marks one with too many.',
      'Undo takes back your last bridge. Hint draws one bridge that must be there, and each hint is counted. '
          'Your time is recorded, and shown if you turn on timers in Settings.',
      'Today\'s board is seven by seven with twelve to sixteen islands, a few minutes on a phone. It can always be '
          'solved by reasoning alone: no guessing is ever needed.',
      'On a keyboard, the arrows move between islands, Enter or Space selects and connects, 0, 1 and 2 set the '
          'bridges between the selected island and the one under the cursor, and Escape clears the selection.',
    ],
  );

  @override
  State<BridgesScreen> createState() => _BridgesScreenState();
}

class _BridgesScreenState extends State<BridgesScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final BridgesPuzzle _puzzle;
  late BridgesState _state;
  GameResult? _result;
  int? _cursor;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  final FocusNode _focus = FocusNode(debugLabel: 'bridges');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = BridgesPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  BridgesState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return BridgesState.initial(_puzzle);
    try {
      return BridgesState.fromJson(_puzzle, saved);
    } on FormatException {
      return BridgesState.initial(_puzzle);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _save();
    _focus.dispose();
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
      setState(() => _state = _state.tick(1));
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

  void _apply(BridgesState next, {bool persist = true}) {
    if (!_playing || identical(next, _state)) return;
    setState(() => _state = next);
    if (persist) _save();
    if (next.isSolved) _complete();
  }

  Future<void> _complete() async {
    if (!_playing) return;
    _completing = true;
    _stopTimer();
    final seconds = _state.elapsedSeconds;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: true,
      seconds: seconds,
      hints: _state.hints,
      shareLines: ['🌉 ${GameResult.formatSeconds(seconds)}'],
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result);
  }

  void _tap(int island) {
    _focus.requestFocus();
    if (!_playing) return;
    setState(() => _cursor = island);
    final selected = _state.selected;
    final next = _state.tap(island);
    if (identical(next, _state)) {
      if (selected != null && selected != island) _notice('Bridges cannot cross.');
      return;
    }
    _apply(next, persist: !identical(next.board, _state.board));
  }

  void _clearSelection() {
    _focus.requestFocus();
    _apply(_state.select(null), persist: false);
  }

  void _setBridges(int count) {
    final selected = _state.selected, cursor = _cursor;
    if (selected == null || cursor == null || selected == cursor) return;
    final pair = _puzzle.layout.pairBetween(selected, cursor);
    if (pair == null) return;
    if (count > 0 && _state.wouldCross(pair)) {
      _notice('Bridges cannot cross.');
      return;
    }
    _apply(_state.setBridges(pair, count));
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1500)));
  }

  void _undo() => _apply(_state.undo());

  Future<void> _hint() async {
    if (!_playing || _state.isSolved) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Draw a bridge for you?'),
        content: const Text('Counts as a hint.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Draw')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.hint());
  }

  void _moveCursor(int dRow, int dCol) {
    final islands = _puzzle.layout.islands;
    final from = _cursor ?? _state.selected;
    if (from == null) {
      setState(() => _cursor = 0);
      return;
    }
    final origin = islands[from];
    int? best;
    var bestKey = 0;
    for (var i = 0; i < islands.length; i++) {
      final dr = islands[i].row - origin.row, dc = islands[i].col - origin.col;
      if (dr * dRow + dc * dCol <= 0) continue;
      final along = dRow != 0 ? dr.abs() : dc.abs();
      final aside = dRow != 0 ? dc.abs() : dr.abs();
      final key = aside * 1000 + along;
      if (best == null || key < bestKey) {
        best = i;
        bestKey = key;
      }
    }
    if (best != null) setState(() => _cursor = best);
  }

  static final Map<LogicalKeyboardKey, int> _countKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final count = _countKeys[key];
    if (count != null) {
      _setBridges(count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveCursor(-1, 0);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveCursor(1, 0);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _moveCursor(0, -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveCursor(0, 1);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      _tap(_cursor ?? _state.selected ?? 0);
    } else if (key == LogicalKeyboardKey.escape) {
      _clearSelection();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? _boardMessage() {
    final fault = _state.fault;
    if (fault == BridgesFault.overCount) return 'An island has more bridges than its number.';
    if (fault == BridgesFault.disconnected) return 'Every island has its number, but they are not all joined up yet.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null;
    final islands = _puzzle.islandCount;
    final message = done ? null : _boardMessage();

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: BridgesScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus.requestFocus(),
          child: Column(
            children: [
              if (!done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (settings.showTimers) ...[
                        Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(GameResult.formatSeconds(_state.elapsedSeconds), style: theme.textTheme.labelMedium),
                        const SizedBox(width: 20),
                      ],
                      Text('${_state.completeIslands} of $islands islands complete', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: BridgesBoard(
                      layout: _puzzle.layout,
                      board: done ? _puzzle.solution : _state.board,
                      selected: done ? null : _state.selected,
                      cursor: done ? null : _cursor,
                      onTap: done ? null : _tap,
                      onBackgroundTap: done ? null : _clearSelection,
                    ),
                  ),
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(message, style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
                ),
              if (done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: Column(
                    children: [
                      Text(result.summary(), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () => _play.showResult(context, result),
                        child: const Text('See result'),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      _Action(id: 'undo', icon: Icons.undo, label: 'Undo', onPressed: _state.canUndo ? _undo : null),
                      _Action(id: 'hint', icon: Icons.lightbulb_outline, label: 'Hint', onPressed: _hint),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.id, required this.icon, required this.label, required this.onPressed});

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        key: ValueKey('bridges-$id'),
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(44, 52),
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: PaperTheme.body(size: 12, weight: 600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
