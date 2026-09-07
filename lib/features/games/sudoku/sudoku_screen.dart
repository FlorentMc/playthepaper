import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../engines/sudoku/sudoku.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'sudoku_board.dart';
import 'sudoku_controls.dart';

class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Sudoku',
    paragraphs: [
      'Fill the grid so that every row, every column and every 3×3 box contains the digits 1 to 9 exactly once. '
          'Tap a cell, then a number. Every puzzle has exactly one solution.',
      'Turn on Notes to pencil small candidate digits into a cell; they are cleared when you place a value. '
          'Undo and Redo step through your moves. Hint fills the selected cell for you, and each hint is counted.',
      'Mistake check marks an entry with a ✕ as soon as it is wrong. It is on by default; switch it off in Settings '
          'if you would rather find your own errors.',
      'Your time is recorded, but only shown if you turn on timers in Settings. On a keyboard, type digits to fill, '
          'use the arrows to move, Backspace to erase and N to toggle notes.',
    ],
  );

  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final SudokuPuzzle _puzzle;
  late SudokuState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  final FocusNode _focus = FocusNode(debugLabel: 'sudoku');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = SudokuPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  SudokuState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return SudokuState.initial(_puzzle);
    try {
      return SudokuState.fromJson(_puzzle, saved);
    } on FormatException {
      return SudokuState.initial(_puzzle);
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

  void _apply(SudokuState next, {bool persist = true}) {
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
    await _play.complete(context, result);
  }

  void _select(int index) {
    _focus.requestFocus();
    _apply(_state.select(index), persist: false);
  }

  void _enter(int digit) {
    final cell = _state.selected;
    var next = _state.input(digit);
    if (cell != null &&
        !identical(next, _state) &&
        !next.notesMode &&
        context.read<Settings>().sudokuMistakeCheck &&
        next.values[cell] != _puzzle.solution[cell]) {
      next = next.recordMistake();
    }
    _apply(next);
  }

  void _erase() => _apply(_state.erase());

  void _toggleNotes() => _apply(_state.toggleNotesMode());

  void _undo() => _apply(_state.undo());

  void _redo() => _apply(_state.redo());

  Future<void> _hint() async {
    if (!_playing || !_state.canEditSelected) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fill this cell?'),
        content: const Text('Counts as a hint.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Fill')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.hint());
  }

  void _move(int dRow, int dCol) {
    final from = _state.selected;
    if (from == null) {
      _apply(_state.select(0), persist: false);
      return;
    }
    final row = (from ~/ 9 + dRow).clamp(0, 8);
    final col = (from % 9 + dCol).clamp(0, 8);
    _apply(_state.select(row * 9 + col), persist: false);
  }

  static final Map<LogicalKeyboardKey, int> _digitKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    var digit = _digitKeys[key];
    final ch = event.character;
    if (digit == null && ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
      digit = ch.codeUnitAt(0) - 0x30;
    }
    if (digit != null) {
      if (digit == 0) {
        _erase();
      } else {
        _enter(digit);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _erase();
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
    if (key == LogicalKeyboardKey.keyN) {
      _toggleNotes();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null;
    final flagged = done
        ? const <int>{}
        : settings.sudokuMistakeCheck
            ? _state.wrongCells()
            : _state.conflicts();
    final showStatus = !done && (settings.showTimers || settings.sudokuMistakeCheck);

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: SudokuScreen.help,
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
              if (showStatus)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (settings.showTimers) ...[
                        Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(GameResult.formatSeconds(_state.elapsedSeconds), style: theme.textTheme.labelMedium),
                      ],
                      if (settings.showTimers && settings.sudokuMistakeCheck) const SizedBox(width: 20),
                      if (settings.sudokuMistakeCheck)
                        Text(
                          'Mistakes ${_state.mistakes}',
                          style: theme.textTheme.labelMedium,
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: SudokuBoard(
                        puzzle: _puzzle,
                        values: done ? _puzzle.solution : _state.values,
                        notesAt: done ? (_) => const {} : _state.notesAt,
                        selected: done ? null : _state.selected,
                        flagged: flagged,
                        onTap: done ? null : _select,
                      ),
                    ),
                  ),
                ),
              ),
              if (!done && _state.isFull && !_state.isSolved)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    'The grid is full, but something is not right yet.',
                    style: theme.textTheme.labelMedium,
                    textAlign: TextAlign.center,
                  ),
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
                SudokuControls(
                  remaining: _state.remainingCounts(),
                  notesMode: _state.notesMode,
                  canUndo: _state.canUndo,
                  canRedo: _state.canRedo,
                  canEdit: _state.canEditSelected,
                  onDigit: _enter,
                  onNotes: _toggleNotes,
                  onUndo: _undo,
                  onRedo: _redo,
                  onErase: _erase,
                  onHint: _hint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
