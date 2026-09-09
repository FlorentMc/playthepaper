import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/tangram/tangram.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'tangram_board.dart';
import 'tangram_controls.dart';

/// Tangram: lay the seven pieces over the day's figure.
class TangramScreen extends StatefulWidget {
  const TangramScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Tangram',
    paragraphs: [
      'Cover the solid figure with all seven pieces. They are the pieces of one square: two large triangles, '
          'a medium one, two small ones, a square and a parallelogram. Every figure uses all seven, and none of '
          'them may lie on top of another.',
      'Drag a piece out of the tray onto the figure. Tap a piece to pick it up, then Turn to swing it round by '
          'an eighth of a turn. Figures are built at quarter turns, so an eighth is always a step on the way to '
          'somewhere. Only the parallelogram has a mirror image of its own, so only that one can be turned over. '
          'Tray sends the picked-up piece back.',
      'Pieces settle onto the board\'s grid, so a piece that looks right is right. The figure is done when none '
          'of it is still showing, and any arrangement that covers it counts, not only the one we had in mind.',
      'A hint drops one piece into place for you and is counted in your result. Reset clears the board. Most '
          'figures take two to six minutes; the outline is the only clue, so the fewer corners it has the longer '
          'it takes.',
      'On a keyboard, Tab moves between the pieces, the arrows nudge the one you have picked up, Enter puts a '
          'piece from the tray onto the middle of the board, R turns it, F turns it over and Backspace sends it '
          'back to the tray.',
      'Your time is recorded, but only shown if you turn on timers in Settings.',
    ],
  );

  @override
  State<TangramScreen> createState() => _TangramScreenState();
}

class _TangramScreenState extends State<TangramScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final TangramPuzzle _puzzle;
  late TangramState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  TangramPiece? _dragging;
  Offset? _dragAt;
  Offset _grab = Offset.zero;
  final FocusNode _focus = FocusNode(debugLabel: 'tangram');
  final GlobalKey _boardKey = GlobalKey();

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = TangramPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  TangramState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return TangramState.initial(_puzzle);
    try {
      return TangramState.fromJson(_puzzle, saved);
    } on FormatException {
      return TangramState.initial(_puzzle);
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

  void _apply(TangramState next, {bool persist = true}) {
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
    final hints = _state.hints;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: true,
      seconds: seconds,
      hints: hints,
      isArchivePlay: _play.isArchivePlay,
      note: '${_puzzle.name} in ${GameResult.formatSeconds(seconds)}',
      shareLines: [
        '🧩 ${GameResult.formatSeconds(seconds)}${hints == 0 ? '' : ' · $hints hint${hints == 1 ? '' : 's'}'}',
      ],
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: 'The figure', reveal: _reveal());
  }

  Widget _reveal() => _TangramReveal(puzzle: _puzzle);

  void _select(TangramPiece? piece) {
    _focus.requestFocus();
    _apply(_state.select(piece), persist: false);
  }

  void _tapBoard(Offset units) {
    _focus.requestFocus();
    final piece = TangramBoard.pieceAt(_state.placed, units);
    if (piece != null) {
      _apply(_state.select(piece), persist: false);
      return;
    }
    final selected = _state.selected;
    if (selected != null && !_state.isPlaced(selected)) {
      _apply(_state.place(selected, units.dx.round(), units.dy.round()));
    }
  }

  void _dropFromTray(TangramPiece piece, Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    final scale = box.size.shortestSide / TangramGeometry.boardUnits;
    _apply(_state.place(piece, (local.dx / scale).round(), (local.dy / scale).round()));
  }

  void _startDrag(TangramPiece piece, Offset grab) {
    _focus.requestFocus();
    final placement = _state.placementOf(piece);
    if (placement == null) return;
    setState(() {
      _dragging = piece;
      _grab = grab;
      _dragAt = Offset(placement.x.toDouble(), placement.y.toDouble());
      _state = _state.select(piece);
    });
  }

  void _dragTo(Offset units) {
    if (_dragging == null) return;
    setState(() => _dragAt = units - _grab);
  }

  void _endDrag() {
    final piece = _dragging;
    final at = _dragAt;
    setState(() {
      _dragging = null;
      _dragAt = null;
    });
    if (piece == null || at == null) return;
    _apply(_state.place(piece, at.dx.round(), at.dy.round()));
  }

  void _turn(int steps) => _apply(_state.turn(steps));

  void _flip() => _apply(_state.flip());

  void _takeBack() => _apply(_state.takeBack());

  void _undo() => _apply(_state.undo());

  void _placeFromTray() {
    final piece = _state.selected;
    if (piece == null || _state.isPlaced(piece)) return;
    _apply(_state.place(piece, TangramGeometry.boardUnits ~/ 2, TangramGeometry.boardUnits ~/ 2));
  }

  void _cycle(int step) {
    final pieces = TangramPiece.values;
    final current = _state.selected;
    final index = current == null ? -1 : pieces.indexOf(current);
    final next = (index + step) % pieces.length;
    _apply(_state.select(pieces[next < 0 ? next + pieces.length : next]), persist: false);
  }

  Future<void> _hint() async {
    if (!_playing) return;
    final confirmed = await _confirm(
      title: 'Place one piece?',
      body: 'One piece drops into place. It counts as a hint.',
      action: 'Place it',
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.hint());
  }

  Future<void> _reset() async {
    if (!_playing || _state.placed.isEmpty) return;
    final confirmed = await _confirm(
      title: 'Clear the board?',
      body: 'Every piece goes back to the tray. Your time keeps running.',
      action: 'Clear',
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.reset());
  }

  Future<bool?> _confirm({required String title, required String body, required String action}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    switch (key) {
      case LogicalKeyboardKey.tab:
        _cycle(shift ? -1 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _apply(_state.nudge(0, -1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _apply(_state.nudge(0, 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _apply(_state.nudge(-1, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _apply(_state.nudge(1, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _turn(shift ? -1 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _flip();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        _placeFromTray();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
      case LogicalKeyboardKey.delete:
        _takeBack();
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
    final selected = _state.selected;
    final placedCount = _state.placed.length;
    final full = placedCount == TangramPiece.values.length;

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: TangramScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
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
                    Text('$placedCount of ${TangramPiece.values.length} placed',
                        style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DragTarget<TangramPiece>(
                    onAcceptWithDetails: done ? null : (d) => _dropFromTray(d.data, d.offset),
                    builder: (context, candidate, rejected) => TangramBoard(
                      key: _boardKey,
                      puzzle: _puzzle,
                      placed: _state.placed,
                      selected: selected,
                      dragging: _dragging,
                      dragAt: _dragAt,
                      finished: done,
                      onTapUnits: done ? null : _tapBoard,
                      onDragPiece: done ? null : _startDrag,
                      onDragTo: done ? null : _dragTo,
                      onDragEnd: done ? null : _endDrag,
                    ),
                  ),
                ),
              ),
            ),
            if (!done && full && !_state.isSolved)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'All seven are down, but some of the figure is still showing.',
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
                      onPressed: () => _play.showResult(context, result,
                          revealTitle: 'The figure', reveal: _reveal()),
                      child: const Text('See result'),
                    ),
                  ],
                ),
              )
            else ...[
              TangramTray(state: _state, onSelect: _select),
              TangramControls(
                canTurn: selected != null && _state.isPlaced(selected),
                canFlip: selected != null && selected.canFlip && _state.isPlaced(selected),
                canTakeBack: selected != null && _state.isPlaced(selected),
                canUndo: _state.canUndo,
                canReset: _state.placed.isNotEmpty,
                onTurn: () => _turn(1),
                onFlip: _flip,
                onTakeBack: _takeBack,
                onUndo: _undo,
                onHint: _hint,
                onReset: _reset,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The figure and its name, shown on the result screen.
class _TangramReveal extends StatelessWidget {
  const _TangramReveal({required this.puzzle});

  final TangramPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(puzzle.name, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: TangramBoard(puzzle: puzzle, placed: const {}, finished: true),
        ),
      ],
    );
  }
}
