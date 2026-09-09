import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/binary/binary.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'binary_board.dart';

/// Binary (Takuzu): fill the grid with ● and ○ under three rules.
class BinaryScreen extends StatefulWidget {
  const BinaryScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Binary',
    paragraphs: [
      'Fill the grid with ● and ○ so that every row and every column holds the same number of each. '
          'No more than two of the same symbol may sit side by side, and no two rows or columns may be identical. '
          'Every puzzle has exactly one solution.',
      'Tap a cell to cycle it from empty to ● to ○ and back. The given symbols are fixed. '
          'Undo takes back your last move, Clear empties the selected cell, and Check marks any cell that is wrong; '
          'each check counts as a hint in your result.',
      'Cells that break a rule are marked with a ! as you go: three in a row, too many of one symbol, or a repeated line.',
      'Today\'s grid is 8×8 with 26 to 34 givens, and it can always be solved by reasoning rather than guessing. '
          'Your time is recorded, but only shown if you turn on timers in Settings.',
      'On a keyboard, use the arrows to move, Space or Enter to cycle a cell, 1 for ●, 0 for ○ and Backspace to clear.',
    ],
  );

  @override
  State<BinaryScreen> createState() => _BinaryScreenState();
}

class _BinaryScreenState extends State<BinaryScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final BinaryPuzzle _puzzle;
  late BinaryState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  int? _lastCheckWrong;
  final FocusNode _focus = FocusNode(debugLabel: 'binary');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = BinaryPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  BinaryState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return BinaryState.initial(_puzzle);
    try {
      return BinaryState.fromJson(_puzzle, saved);
    } on FormatException {
      return BinaryState.initial(_puzzle);
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

  void _apply(BinaryState next, {bool persist = true}) {
    if (!_playing || identical(next, _state)) return;
    setState(() {
      _state = next;
      if (persist) _lastCheckWrong = null;
    });
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
      shareLines: ['●○ ${_puzzle.size}×${_puzzle.size}'],
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result);
  }

  void _tap(int index) {
    _focus.requestFocus();
    if (_state.isGiven(index)) {
      _apply(_state.select(index), persist: false);
    } else {
      _apply(_state.cycle(index));
    }
  }

  void _cycleSelected() {
    final i = _state.selected;
    if (i == null) return;
    _apply(_state.cycle(i));
  }

  void _setSelected(int value) {
    final i = _state.selected;
    if (i == null) return;
    _apply(_state.setValue(i, value));
  }

  void _clear() => _setSelected(BinaryRules.empty);

  void _undo() => _apply(_state.undo());

  void _check() {
    if (!_playing) return;
    final next = _state.check();
    setState(() {
      _state = next;
      _lastCheckWrong = next.flagged.length;
    });
    _save();
  }

  void _move(int dRow, int dCol) {
    final from = _state.selected;
    if (from == null) {
      _apply(_state.select(0), persist: false);
      return;
    }
    final size = _puzzle.size;
    final row = (from ~/ size + dRow).clamp(0, size - 1);
    final col = (from % size + dCol).clamp(0, size - 1);
    _apply(_state.select(row * size + col), persist: false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      _setSelected(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _setSelected(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _cycleSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _statusLine() {
    final wrong = _lastCheckWrong;
    if (wrong != null) {
      if (wrong == 0) return 'Nothing wrong so far.';
      return wrong == 1 ? '1 cell is wrong.' : '$wrong cells are wrong.';
    }
    if (_state.isFull && !_state.isSolved) return 'The grid is full, but something is not right yet.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null;
    final status = done ? null : _statusLine();
    final canEdit = !done && _state.selected != null && !_state.isGiven(_state.selected!);
    var hasEntries = false;
    for (var i = 0; i < _state.values.length && !hasEntries; i++) {
      hasEntries = !_state.isGiven(i) && _state.values[i] != BinaryRules.empty;
    }

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: BinaryScreen.help,
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
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: BinaryBoard(
                        puzzle: _puzzle,
                        values: done ? _puzzle.solution : _state.values,
                        selected: done ? null : _state.selected,
                        conflicts: done ? const {} : _state.conflicts(),
                        flagged: done ? const {} : _state.flagged,
                        onTap: done ? null : _tap,
                      ),
                    ),
                  ),
                ),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(status, style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
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
                      _Action(
                        id: 'clear',
                        icon: Icons.backspace_outlined,
                        label: 'Clear',
                        onPressed: canEdit && _state.values[_state.selected!] != BinaryRules.empty ? _clear : null,
                      ),
                      _Action(
                        id: 'check',
                        icon: Icons.fact_check_outlined,
                        label: 'Check',
                        onPressed: hasEntries ? _check : null,
                      ),
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
        key: ValueKey('binary-$id'),
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
