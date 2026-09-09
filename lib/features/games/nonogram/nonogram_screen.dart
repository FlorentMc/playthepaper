import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/nonogram/nonogram.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'nonogram_board.dart';

/// Nonogram: the numbers beside each line say how many cells to fill, and a
/// picture appears.
class NonogramScreen extends StatefulWidget {
  const NonogramScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Nonogram',
    paragraphs: [
      'The numbers beside a row or above a column give the runs of filled cells in it, in order, with at least '
          'one blank between runs. A row marked 3 1 has three filled cells, then a gap, then one more. Fill the '
          'right cells and a small picture appears.',
      'Tap a cell to step it on: blank, filled, crossed, blank again. A cross is your own note that a cell is '
          'definitely empty; only filled cells count towards the picture. Drag across a line to paint several '
          'cells at once, and use the Fill and Cross buttons to choose what a drag paints.',
      'Undo takes back your last cell or stroke. Check row marks the wrong cells in the row you are on with a '
          'red outline and an exclamation mark, and each check is counted as a hint. Reset clears the whole grid '
          'and asks first.',
      'A clue fades and is struck through once that line matches it exactly. Every puzzle has one answer and can '
          'be reached by reasoning alone: no guessing is ever needed.',
      'Today\'s picture is ten by ten on even dates and five by five on odd ones, so a few minutes on a phone. '
          'Your time is recorded, and shown if you turn on timers in Settings.',
      'On a keyboard the arrows move the cursor, Space fills a cell, X crosses it, Enter steps it on, Backspace '
          'clears it, F swaps what a drag paints and C checks the row you are on.',
    ],
    example: _helpExample,
  );

  @override
  State<NonogramScreen> createState() => _NonogramScreenState();
}

final NonogramPuzzle _example = NonogramPuzzle.fromPicture(picture: const ['010', '111', '010'], title: 'Cross');

/// A worked 3×3: the clues on the left and top, and the picture they give.
Widget _helpExample(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('A worked example', style: PaperTheme.body(size: 15, weight: 700, color: theme.colorScheme.onSurface)),
      const SizedBox(height: 8),
      Text(
        'Every row and every column reads 1, 3, 1 down the middle: one cell, three cells, one cell. Only one '
            'picture fits.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 160,
          height: 160,
          child: NonogramBoard(
            puzzle: _example,
            marks: List<CellMark>.filled(9, CellMark.unknown),
            finished: true,
            maxCell: 34,
          ),
        ),
      ),
    ],
  );
}

class _NonogramScreenState extends State<NonogramScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final NonogramPuzzle _puzzle;
  late NonogramState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  CellMark? _strokeMark;
  bool _strokeStarted = false;
  final FocusNode _focus = FocusNode(debugLabel: 'nonogram');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = NonogramPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  NonogramState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return NonogramState.initial(_puzzle);
    try {
      return NonogramState.fromJson(_puzzle, saved);
    } on FormatException {
      return NonogramState.initial(_puzzle);
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

  void _apply(NonogramState next, {bool persist = true}) {
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
      shareLines: ['🖼 ${_puzzle.width}×${_puzzle.height} in ${GameResult.formatSeconds(seconds)}'],
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: 'The picture', reveal: _reveal());
  }

  Widget _reveal() => Builder(
        builder: (context) => Column(
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: NonogramBoard(puzzle: _puzzle, marks: _state.cells, finished: true, showClues: false, maxCell: 22),
            ),
            const SizedBox(height: 10),
            Text(_puzzle.title, style: PaperTheme.display(size: 20, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      );

  void _tap(int index) {
    _focus.requestFocus();
    if (!_playing) return;
    _apply(_state.cycle(index).setCursor(index));
  }

  void _strokeStart(int index) {
    _focus.requestFocus();
    if (!_playing) return;
    _strokeMark = _state.strokeTarget(index);
    _strokeStarted = false;
  }

  void _strokeCell(int index) {
    final mark = _strokeMark;
    if (mark == null || !_playing) return;
    final next = _state.set(index, mark, extendStroke: _strokeStarted);
    if (identical(next, _state)) return;
    _strokeStarted = true;
    _apply(next.setCursor(index), persist: false);
  }

  void _strokeEnd() {
    _strokeMark = null;
    if (_strokeStarted) _save();
    _strokeStarted = false;
  }

  void _undo() => _apply(_state.undo());

  void _redo() => _apply(_state.redo());

  void _setMode(PaintMode mode) {
    _focus.requestFocus();
    _apply(_state.setMode(mode), persist: false);
  }

  void _selectRow(int row) {
    _focus.requestFocus();
    _apply(_state.setCursor(row * _puzzle.width), persist: false);
  }

  void _move(int dRow, int dCol) => _apply(_state.moveCursor(dRow, dCol), persist: false);

  void _mark(CellMark mark) {
    final cursor = _state.cursor;
    if (cursor == null) {
      _apply(_state.setCursor(0), persist: false);
      return;
    }
    _apply(_state.toggle(cursor, mark));
  }

  void _clearCell() {
    final cursor = _state.cursor;
    if (cursor != null) _apply(_state.set(cursor, CellMark.unknown));
  }

  void _cycleCursor() {
    final cursor = _state.cursor;
    if (cursor == null) {
      _apply(_state.setCursor(0), persist: false);
      return;
    }
    _apply(_state.cycle(cursor));
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 1500)));
  }

  Future<void> _checkRow() async {
    if (!_playing) return;
    final row = _state.cursorRow;
    if (row == null) {
      _notice('Choose a row first, by tapping a cell or its clue.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Check row ${row + 1}?'),
        content: const Text('Wrong cells are outlined. Counts as a hint.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Check')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final wrong = _state.wrongInRow(row).length;
    _apply(_state.checkRow(row));
    _notice(wrong == 0 ? 'Nothing wrong in row ${row + 1}.' : '$wrong wrong ${wrong == 1 ? 'cell' : 'cells'} in row ${row + 1}.');
  }

  Future<void> _reset() async {
    if (!_playing || _state.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the grid?'),
        content: const Text('Every mark goes. Your time and hints stay as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.reset());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1, 0);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _move(1, 0);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _move(0, -1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(0, 1);
    } else if (key == LogicalKeyboardKey.space) {
      _mark(CellMark.filled);
    } else if (key == LogicalKeyboardKey.keyX) {
      _mark(CellMark.crossed);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _cycleCursor();
    } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _clearCell();
    } else if (key == LogicalKeyboardKey.keyF) {
      _apply(_state.toggleMode(), persist: false);
    } else if (key == LogicalKeyboardKey.keyC) {
      _checkRow();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  int get _rowsDone {
    var n = 0;
    for (var r = 0; r < _puzzle.height; r++) {
      if (_state.rowSatisfied(r)) n++;
    }
    return n;
  }

  int get _colsDone {
    var n = 0;
    for (var c = 0; c < _puzzle.width; c++) {
      if (_state.columnSatisfied(c)) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null;

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: NonogramScreen.help,
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
                      Text(
                        'Rows $_rowsDone/${_puzzle.height} · Columns $_colsDone/${_puzzle.width}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: NonogramBoard(
                      puzzle: _puzzle,
                      marks: _state.cells,
                      cursor: done ? null : _state.cursor,
                      flagged: done ? const {} : _state.flagged,
                      rowSatisfied: done ? null : _state.rowSatisfied,
                      columnSatisfied: done ? null : _state.columnSatisfied,
                      finished: done,
                      onTap: done ? null : _tap,
                      onSelectRow: done ? null : _selectRow,
                      onStrokeStart: done ? null : _strokeStart,
                      onStrokeCell: done ? null : _strokeCell,
                      onStrokeEnd: done ? null : _strokeEnd,
                    ),
                  ),
                ),
              ),
              if (done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: Column(
                    children: [
                      Text(_puzzle.title, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Text(result.summary(), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () => _play.showResult(context, result, revealTitle: 'The picture', reveal: _reveal()),
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
                      _Action(
                        id: 'fill',
                        icon: Icons.square,
                        label: 'Fill',
                        selected: _state.mode == PaintMode.fill,
                        onPressed: () => _setMode(PaintMode.fill),
                      ),
                      _Action(
                        id: 'cross',
                        icon: Icons.close,
                        label: 'Cross',
                        selected: _state.mode == PaintMode.cross,
                        onPressed: () => _setMode(PaintMode.cross),
                      ),
                      _Action(id: 'undo', icon: Icons.undo, label: 'Undo', onPressed: _state.canUndo ? _undo : null),
                      _Action(id: 'redo', icon: Icons.redo, label: 'Redo', onPressed: _state.canRedo ? _redo : null),
                      _Action(id: 'check', icon: Icons.rule, label: 'Check', spoken: 'Check row', onPressed: _checkRow),
                      _Action(id: 'reset', icon: Icons.restart_alt, label: 'Reset', onPressed: _state.isEmpty ? null : _reset),
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
  const _Action({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.spoken,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Marked with a bar as well as a colour, so the choice is not colour alone.
  final bool selected;

  /// A fuller label for screen readers where the button is abbreviated.
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final name = spoken ?? label;
    return Expanded(
      child: Semantics(
        key: ValueKey('nonogram-$id'),
        button: true,
        enabled: onPressed != null,
        selected: selected,
        label: selected ? '$name, on' : name,
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            minimumSize: const Size(44, 56),
            backgroundColor: selected ? colors.cellSelected : null,
            foregroundColor: selected ? theme.colorScheme.onSurface : null,
            splashFactory: MediaQuery.disableAnimationsOf(context) ? NoSplash.splashFactory : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 2),
              Text(label, style: PaperTheme.body(size: 11, weight: 600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Container(
                height: 2,
                width: 18,
                margin: const EdgeInsets.only(top: 2),
                color: selected ? theme.colorScheme.onSurface : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
