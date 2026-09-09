import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/target/target.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'target_board.dart';

/// Target: combine six tiles with + − × ÷ to make the number at the top.
class TargetScreen extends StatefulWidget {
  const TargetScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Target',
    paragraphs: [
      'Make the target number from the six tiles. Pick a tile, pick an operation, then pick a second tile: '
          'the two tiles are taken off the table and their answer becomes a new tile you can use again.',
      'Every tile may be used once. Every answer along the way must be a whole number above zero, '
          'so a subtraction may not go below zero and a division must come out exactly.',
      'You do not have to use all six tiles. Undo takes back your last step and Reset clears the table. '
          'If you would rather see one way to the target, Show a solution ends the puzzle and counts as a hint.',
      'Your result records the number you reached: exactly the target, or how close you came. '
          'Today\'s target is 101 to 999 and can always be made, usually needing four or five of the tiles. '
          'Your time is recorded, but only shown if you turn on timers in Settings.',
      'On a keyboard, press 1 to 6 to pick the tile in that place, +, −, × or ÷ for the operation, '
          'the left and right arrows to move between tiles and Enter to pick the one you are on, '
          'the up and down arrows to change the operation, Backspace to undo and Escape to drop a pick.',
    ],
  );

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final TargetPuzzle _puzzle;
  late TargetState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  int? _chosen;
  TargetOp? _op;
  int _cursor = 0;
  String? _message;
  final FocusNode _focus = FocusNode(debugLabel: 'target');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = TargetPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  TargetState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return TargetState.initial(_puzzle);
    try {
      return TargetState.fromJson(_puzzle, saved);
    } on FormatException {
      return TargetState.initial(_puzzle);
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

  bool get _playing => _result == null && !_completing && !_state.isOver;

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

  void _clearPick() {
    _chosen = null;
    _op = null;
  }

  /// Picks the tile with [id]: the first of a step, a change of mind, or the
  /// second, which makes the step.
  void _pickTile(int id) {
    _focus.requestFocus();
    if (!_playing) return;
    final at = _state.tiles.indexWhere((t) => t.id == id);
    if (at == -1) return;
    setState(() {
      _cursor = at;
      _message = null;
      if (_chosen == id) {
        _clearPick();
        return;
      }
      if (_chosen == null || _op == null) {
        _chosen = id;
        return;
      }
      final op = _op!;
      final a = _state.tile(_chosen!)!.value;
      final b = _state.tile(id)!.value;
      final next = _state.apply(_chosen!, op, id);
      if (identical(next, _state)) {
        _message = op == TargetOp.divide
            ? '$a ${op.symbol} $b does not come out exactly.'
            : '$a ${op.symbol} $b would go below one.';
        return;
      }
      _state = next;
      _clearPick();
      _cursor = next.tiles.indexWhere((t) => t.step == next.steps.length - 1).clamp(0, next.tiles.length - 1);
    });
    _save();
    if (_state.isSolved) _complete();
  }

  void _pickOp(TargetOp op) {
    _focus.requestFocus();
    if (!_playing) return;
    setState(() {
      _message = _chosen == null ? 'Pick a tile first.' : null;
      _op = _op == op ? null : op;
    });
  }

  void _undo() {
    if (!_playing || !_state.canUndo) return;
    setState(() {
      _state = _state.undo();
      _clearPick();
      _message = null;
      _cursor = _cursor.clamp(0, _state.tiles.length - 1);
    });
    _save();
  }

  void _reset() {
    if (!_playing || !_state.canUndo) return;
    setState(() {
      _state = _state.reset();
      _clearPick();
      _message = null;
      _cursor = 0;
    });
    _save();
  }

  Future<void> _giveUp() async {
    if (!_playing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show a solution?'),
        content: const Text('This ends the puzzle. Your result will record how close you came.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Show it')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_playing) return;
    setState(() {
      _state = _state.giveUp();
      _clearPick();
      _message = null;
    });
    await _complete();
  }

  Future<void> _complete() async {
    if (_result != null || _completing) return;
    _completing = true;
    _stopTimer();
    final solved = _state.isSolved;
    final off = _state.closest?.$2;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: solved,
      seconds: _state.elapsedSeconds,
      hints: _state.gaveUp ? 1 : 0,
      note: _state.note,
      shareLines: [solved ? '🎯 ${_puzzle.target} exactly' : '🎯 ${off == null ? 'no route found' : '$off off'}'],
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: 'One way to the target', reveal: _reveal());
  }

  Widget _reveal() => _SolutionReveal(puzzle: _puzzle);

  void _moveCursor(int delta) {
    if (!_playing) return;
    final count = _state.tiles.length;
    if (count == 0) return;
    setState(() => _cursor = (_cursor + delta + count) % count);
  }

  void _cycleOp(int delta) {
    if (!_playing) return;
    final ops = TargetOp.values;
    final from = _op == null ? (delta > 0 ? -1 : 0) : ops.indexOf(_op!);
    _pickOp(ops[(from + delta + ops.length) % ops.length]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    const digits = [
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
      [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
      [LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad5],
      [LogicalKeyboardKey.digit6, LogicalKeyboardKey.numpad6],
    ];
    for (var i = 0; i < digits.length; i++) {
      if (digits[i].contains(key)) {
        if (i < _state.tiles.length) _pickTile(_state.tiles[i].id);
        return KeyEventResult.handled;
      }
    }
    final op = _opFor(event);
    if (op != null) {
      _pickOp(op);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      if (_cursor < _state.tiles.length) _pickTile(_state.tiles[_cursor].id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveCursor(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveCursor(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _cycleOp(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _cycleOp(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      if (_chosen != null || _op != null) {
        setState(_clearPick);
      } else {
        _undo();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(_clearPick);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static final Map<LogicalKeyboardKey, TargetOp> _opKeys = {
    LogicalKeyboardKey.numpadAdd: TargetOp.add,
    LogicalKeyboardKey.add: TargetOp.add,
    LogicalKeyboardKey.numpadSubtract: TargetOp.subtract,
    LogicalKeyboardKey.minus: TargetOp.subtract,
    LogicalKeyboardKey.numpadMultiply: TargetOp.multiply,
    LogicalKeyboardKey.asterisk: TargetOp.multiply,
    LogicalKeyboardKey.numpadDivide: TargetOp.divide,
    LogicalKeyboardKey.slash: TargetOp.divide,
  };

  static TargetOp? _opFor(KeyEvent event) {
    final byLogical = _opKeys[event.logicalKey];
    if (byLogical != null) return byLogical;
    final ch = event.character;
    return ch == null || ch.length != 1 ? null : TargetOp.fromChar(ch);
  }

  String _pending() {
    final chosen = _chosen == null ? null : _state.tile(_chosen!);
    if (chosen == null) return 'Pick a tile.';
    if (_op == null) return '${chosen.value} …';
    return '${chosen.value} ${_op!.symbol} …';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final result = _result;
    final done = result != null;

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: TargetScreen.help,
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
              if (!done && settings.showTimers)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(GameResult.formatSeconds(_state.elapsedSeconds), style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    children: [
                      TargetHeader(target: _puzzle.target),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _state.tiles.length; i++)
                            TargetTileButton(
                              tile: _state.tiles[i],
                              position: i + 1,
                              isChosen: !done && _state.tiles[i].id == _chosen,
                              isCursor: !done && i == _cursor,
                              onPressed: done ? null : () => _pickTile(_state.tiles[i].id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!done) ...[
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            for (final op in TargetOp.values)
                              TargetOpButton(op: op, isChosen: _op == op, onPressed: () => _pickOp(op)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_pending(), style: PaperTheme.body(size: 15, weight: 600, color: colors.subtle)),
                        const SizedBox(height: 10),
                      ],
                      TargetStepList(steps: _state.steps, target: _puzzle.target),
                      if (done) ...[
                        const SizedBox(height: 14),
                        Text(result.note ?? result.summary(), style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _SolutionReveal(puzzle: _puzzle),
                      ],
                    ],
                  ),
                ),
              ),
              if (_message != null && !done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    _message!,
                    style: PaperTheme.body(size: 13, weight: 600, color: colors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: FilledButton(
                    onPressed: () => _play.showResult(
                      context,
                      result,
                      revealTitle: 'One way to the target',
                      reveal: _reveal(),
                    ),
                    child: const Text('See result'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      _Action(id: 'undo', icon: Icons.undo, label: 'Undo', onPressed: _state.canUndo ? _undo : null),
                      _Action(
                        id: 'reset',
                        icon: Icons.restart_alt,
                        label: 'Reset',
                        onPressed: _state.canUndo ? _reset : null,
                      ),
                      _Action(id: 'giveup', icon: Icons.lightbulb_outline, label: 'Show a solution', onPressed: _giveUp),
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

class _SolutionReveal extends StatelessWidget {
  const _SolutionReveal({required this.puzzle});

  final TargetPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('ONE WAY TO ${puzzle.target}', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          puzzle.solution.display,
          style: PaperTheme.body(size: 18, weight: 600, color: theme.colorScheme.onSurface),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text('Any route to the target counts.', style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
      ],
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
        key: ValueKey('target-$id'),
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
