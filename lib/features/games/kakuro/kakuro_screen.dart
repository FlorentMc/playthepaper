import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../engines/kakuro/kakuro.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'kakuro_board.dart';
import 'kakuro_controls.dart';

/// Kakuro: crossing sums with the digits 1 to 9.
class KakuroScreen extends StatefulWidget {
  const KakuroScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Kakuro',
    paragraphs: [
      'Fill every white cell with a digit from 1 to 9. Each clue gives the sum of the run of cells to its right '
          '(top number) or below it (bottom number). No digit repeats within a run. Every puzzle has exactly one '
          'solution, and each can be worked out by reasoning alone, with no guessing.',
      'Tap a cell, then a number. A tick beside a clue means that run adds up; an exclamation mark means it does '
          'not, or a digit is repeated. Turn on Notes to pencil small candidates into a cell; placing a digit '
          'clears them. Undo and Redo step through your moves.',
      'Check marks any wrong digits with a cross, and Reveal fills the selected cell for you. Each check or reveal '
          'counts as a hint in your result. Your time is recorded, but only shown if you turn on timers in Settings.',
      'On a keyboard: type digits to fill, use the arrows to move between cells, Backspace to erase, Space or N '
          'to toggle notes, Z to undo, Y to redo, C to check and R to reveal.',
      'The daily board is 6×6 and takes a few minutes: about the length of a cup of tea.',
    ],
  );

  @override
  State<KakuroScreen> createState() => _KakuroScreenState();
}

class _KakuroScreenState extends State<KakuroScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final KakuroPuzzle _puzzle;
  late KakuroState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  final FocusNode _focus = FocusNode(debugLabel: 'kakuro');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = KakuroPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  KakuroState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return KakuroState.initial(_puzzle);
    try {
      return KakuroState.fromJson(_puzzle, saved);
    } on FormatException {
      return KakuroState.initial(_puzzle);
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

  void _apply(KakuroState next, {bool persist = true}) {
    if (!_playing || identical(next, _state)) return;
    setState(() => _state = next);
    if (persist) _save();
    if (next.isSolved) _complete();
  }

  Future<void> _complete() async {
    if (!_playing) return;
    _completing = true;
    _stopTimer();
    final time = GameResult.formatSeconds(_state.elapsedSeconds);
    final hints = _state.hints;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: true,
      seconds: _state.elapsedSeconds,
      hints: hints,
      shareLines: ['➕ $time${hints == 0 ? '' : ' · $hints hint${hints == 1 ? '' : 's'}'}'],
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result);
  }

  void _select(int index) {
    _focus.requestFocus();
    if (!_puzzle.grid.isWhite(index)) return;
    _apply(_state.select(index), persist: false);
  }

  void _enter(int digit) => _apply(_state.input(digit));

  void _erase() => _apply(_state.erase());

  void _toggleNotes() => _apply(_state.toggleNotesMode());

  void _undo() => _apply(_state.undo());

  void _redo() => _apply(_state.redo());

  bool get _hasEntries => _puzzle.whiteCells.any((i) => _state.values[i] != 0);

  void _check() {
    if (!_playing || !_hasEntries) return;
    final next = _state.check();
    _apply(next);
    final n = next.wrong.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(n == 0 ? 'No mistakes so far.' : '$n wrong ${n == 1 ? 'digit' : 'digits'} marked.'),
        duration: const Duration(milliseconds: 1500),
      ));
  }

  Future<void> _reveal() async {
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
    _apply(_state.revealCell());
  }

  /// Moves the cursor to the next white cell in a direction, staying put
  /// when there is none.
  void _move(int dRow, int dCol) {
    final grid = _puzzle.grid;
    final from = _state.selected;
    if (from == null) {
      _apply(_state.select(grid.whiteCells.first), persist: false);
      return;
    }
    var r = grid.rowOf(from) + dRow;
    var c = grid.colOf(from) + dCol;
    while (r >= 0 && r < grid.height && c >= 0 && c < grid.width) {
      final i = grid.indexOf(r, c);
      if (grid.isWhite(i)) {
        _apply(_state.select(i), persist: false);
        return;
      }
      r += dRow;
      c += dCol;
    }
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
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1);
    } else if (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.space) {
      _toggleNotes();
    } else if (key == LogicalKeyboardKey.keyZ) {
      _undo();
    } else if (key == LogicalKeyboardKey.keyY) {
      _redo();
    } else if (key == LogicalKeyboardKey.keyC) {
      _check();
    } else if (key == LogicalKeyboardKey.keyR) {
      _reveal();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? _selectionCaption() {
    final sel = _state.selected;
    if (sel == null || !_puzzle.grid.isWhite(sel)) return null;
    final parts = <String>[];
    for (final run in _puzzle.grid.runsThrough(sel)) {
      parts.add('${run.sum} ${run.direction} in ${run.length}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null;
    final caption = done ? null : _selectionCaption();
    final showStatus = !done && (settings.showTimers || _state.hints > 0);

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: KakuroScreen.help,
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
                      if (settings.showTimers && _state.hints > 0) const SizedBox(width: 20),
                      if (_state.hints > 0)
                        Text(
                          '${_state.hints} hint${_state.hints == 1 ? '' : 's'}',
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
                      aspectRatio: _puzzle.width / _puzzle.height,
                      child: KakuroBoard(
                        grid: _puzzle.grid,
                        values: done ? _puzzle.solution : _state.values,
                        notesAt: done ? (_) => const {} : _state.notesAt,
                        selected: done ? null : _state.selected,
                        flagged: done ? const {} : _state.wrong,
                        conflicts: done ? const {} : _state.conflicts(),
                        runStatus: done ? (_) => RunStatus.met : _state.runStatus,
                        onTap: done ? null : _select,
                      ),
                    ),
                  ),
                ),
              ),
              if (!done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    _state.isFull && !_state.isSolved
                        ? 'Every cell is filled, but something is not right yet.'
                        : caption ?? 'Tap a white cell to begin.',
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
                KakuroControls(
                  notesMode: _state.notesMode,
                  canUndo: _state.canUndo,
                  canRedo: _state.canRedo,
                  canEdit: _state.canEditSelected,
                  canCheck: _hasEntries,
                  onDigit: _enter,
                  onNotes: _toggleNotes,
                  onUndo: _undo,
                  onRedo: _redo,
                  onErase: _erase,
                  onCheck: _check,
                  onReveal: _reveal,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
