import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../engines/regions/regions.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'regions_board.dart';
import 'regions_controls.dart';

/// Regions: fill each bordered region of N cells with 1 to N, and never let
/// equal digits touch, corners included.
class RegionsScreen extends StatefulWidget {
  const RegionsScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Regions',
    paragraphs: [
      'Fill every cell with a digit. A region, marked by thick borders, holds the digits 1 up to its size once each: '
          'a lone cell is always 1, a region of five holds 1 to 5. The same digit never touches itself, not even at a corner.',
      'Tap a cell, then a number; the keys only offer digits that fit that region. Turn on Notes to pencil in candidates, '
          'which clear when you place a value. A digit that breaks a rule is marked with a cross. Undo steps back.',
      'Check marks any digits that are wrong, and Reveal fills the selected cell. Each use counts as a hint in your result.',
      'The daily board is 6×6 with about eight starting digits. Every board can be solved by reasoning alone, with no guessing, '
          'in a few unhurried minutes.',
      'Your time is recorded, but only shown if you turn on timers in Settings. On a keyboard, type digits to fill, use the '
          'arrows to move, Backspace to erase, N for notes, U to undo, C to check and R to reveal.',
    ],
  );

  @override
  State<RegionsScreen> createState() => _RegionsScreenState();
}

class _RegionsScreenState extends State<RegionsScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final RegionsPuzzle _puzzle;
  late RegionsState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  final FocusNode _focus = FocusNode(debugLabel: 'regions');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = RegionsPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  RegionsState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return RegionsState.initial(_puzzle);
    try {
      return RegionsState.fromJson(_puzzle, saved);
    } on FormatException {
      return RegionsState.initial(_puzzle);
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

  void _apply(RegionsState next, {bool persist = true}) {
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
      shareLines: _state.shareLines(),
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result);
  }

  void _select(int index) {
    _focus.requestFocus();
    _apply(_state.select(index), persist: false);
  }

  void _enter(int digit) => _apply(_state.input(digit));

  void _erase() => _apply(_state.erase());

  void _toggleNotes() => _apply(_state.toggleNotesMode());

  void _undo() => _apply(_state.undo());

  void _check() {
    if (!_playing || !_state.hasEntries) return;
    final next = _state.check();
    final wrong = next.flagged.length;
    _apply(next);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(wrong == 0 ? 'No wrong digits so far.' : '$wrong wrong digit${wrong == 1 ? '' : 's'} marked.'),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _reveal() async {
    if (!_playing || !_state.canEditSelected) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reveal this cell?'),
        content: const Text('Counts as a hint.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reveal')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.reveal());
  }

  void _move(int dRow, int dCol) {
    final from = _state.selected;
    if (from == null) {
      _apply(_state.select(0), persist: false);
      return;
    }
    final grid = _puzzle.grid;
    final row = (grid.rowOf(from) + dRow).clamp(0, grid.height - 1);
    final col = (grid.colOf(from) + dCol).clamp(0, grid.width - 1);
    _apply(_state.select(row * grid.width + col), persist: false);
  }

  bool _digitFits(int digit) {
    final i = _state.selected;
    return i != null && !_state.isGiven(i) && digit <= _puzzle.grid.sizeOf(i);
  }

  static final Map<LogicalKeyboardKey, int> _digitKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    var digit = _digitKeys[key];
    final ch = event.character;
    if (digit == null && ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x35) {
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
    if (key == LogicalKeyboardKey.keyU) {
      _undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      _check();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      _reveal();
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
    final showStatus = !done && (settings.showTimers || _state.hints > 0);

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: RegionsScreen.help,
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
                        Text('${_state.hints} hint${_state.hints == 1 ? '' : 's'}', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AspectRatio(
                      aspectRatio: _puzzle.width / _puzzle.height,
                      child: RegionsBoard(
                        puzzle: _puzzle,
                        values: done ? _puzzle.solution : _state.values,
                        notesAt: done ? (_) => const {} : _state.notesAt,
                        selected: done ? null : _state.selected,
                        wrong: done ? const {} : _state.flagged,
                        conflicts: done ? const {} : _state.conflicts(),
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
                    'The board is full, but something is not right yet.',
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
                RegionsControls(
                  maxDigit: _puzzle.grid.maxDigit,
                  digitEnabled: _digitFits,
                  notesMode: _state.notesMode,
                  canUndo: _state.canUndo,
                  canEdit: _state.canEditSelected,
                  canCheck: _state.hasEntries,
                  onDigit: _enter,
                  onNotes: _toggleNotes,
                  onUndo: _undo,
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
