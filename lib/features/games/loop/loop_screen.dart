import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/loop/loop.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../../storage/local_store.dart';
import '../../play/play_context.dart';
import 'loop_board.dart';

/// Loop: draw one closed line around the clues, Slitherlink style.
class LoopScreen extends StatefulWidget {
  const LoopScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Loop',
    paragraphs: [
      'Join the dots into one single closed loop. A number says exactly how many of that cell\'s four sides the '
          'loop uses, so a 0 has no line round it at all and a 3 has all but one. Cells without a number are free: '
          'the loop may use any of their sides, or none.',
      'The loop never branches and never crosses itself: at every dot it either passes straight through, turns, or '
          'stays away. It is finished when every number is right and the line comes back to where it started, in one '
          'piece.',
      'Tap between two dots to draw a line there, and tap it again to rub it out. Long press instead to pencil a '
          'small ✕ where you are sure the loop does not go; the Crosses button switches taps to do the same. A tick '
          'marks a number that has its lines, a ✕ marks one that can no longer be right, and a dot turns red when '
          'three lines meet there.',
      'Undo and Redo step through your marks. Hint fills in one line or cross for you, and each hint is counted. '
          'Your time is recorded, and shown while you play if you turn on timers in Settings.',
      'Today\'s board is six cells by six, with fourteen to twenty clues. It can always be finished by reasoning '
          'alone, with a handful of places where you have to try a line and see that it fails: a few minutes on a '
          'phone, and never a guess.',
      'On a keyboard, the arrows move the cursor from edge to edge — left and right along a row of edges, up and '
          'down onto the next row, which alternates between the across edges and the down ones. Enter or Space '
          'draws and rubs out a line, and X marks a cross.',
    ],
  );

  @override
  State<LoopScreen> createState() => _LoopScreenState();
}

class _LoopScreenState extends State<LoopScreen> with WidgetsBindingObserver {
  static const _ticksPerSave = 10;

  late final LoopPuzzle _puzzle;
  late LoopState _state;
  GameResult? _result;
  Timer? _timer;
  int _ticksSinceSave = 0;
  bool _completing = false;
  final FocusNode _focus = FocusNode(debugLabel: 'loop');

  PlayContext get _play => widget.play;

  LoopGrid get _grid => _puzzle.grid;

  @override
  void initState() {
    super.initState();
    _puzzle = LoopPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    WidgetsBinding.instance.addObserver(this);
    if (_result == null) _startTimer();
  }

  LoopState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return LoopState.initial(_puzzle);
    try {
      return LoopState.fromJson(_puzzle, saved);
    } on FormatException {
      return LoopState.initial(_puzzle);
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

  void _apply(LoopState next, {bool persist = true}) {
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
      shareLines: ['⭕ ${GameResult.formatSeconds(seconds)}'],
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result);
  }

  void _tap(int edge) {
    _focus.requestFocus();
    _apply(_state.tap(edge));
  }

  void _cross(int edge) {
    _focus.requestFocus();
    _apply(_state.toggleCross(edge).select(edge));
  }

  void _toggleMode() => _apply(_state.toggleCrossMode());

  void _undo() => _apply(_state.undo());

  void _redo() => _apply(_state.redo());

  Future<void> _hint() async {
    if (!_playing || _state.isSolved) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fill in one edge for you?'),
        content: const Text('Counts as a hint.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Fill in')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _apply(_state.hint());
  }

  /// An edge as a point on the lattice of dots, edges and cell centres: a
  /// horizontal edge sits on an even row, a vertical one on an odd row.
  (int, int) _lattice(int edge) => _grid.isHorizontal(edge)
      ? (2 * _grid.edgeRow(edge), 2 * _grid.edgeCol(edge) + 1)
      : (2 * _grid.edgeRow(edge) + 1, 2 * _grid.edgeCol(edge));

  int _edgeAt(int row, int col) =>
      row.isEven ? _grid.h(row ~/ 2, (col - 1) ~/ 2) : _grid.v((row - 1) ~/ 2, col ~/ 2);

  void _move(int dRow, int dCol) {
    final from = _state.cursor;
    if (from == null) {
      _apply(_state.select(_grid.h(0, 0)), persist: false);
      return;
    }
    final (row, col) = _lattice(from);
    final maxRow = 2 * _grid.height, maxCol = 2 * _grid.width;
    var nextRow = row + dRow, nextCol = col;
    if (dRow != 0) {
      if (nextRow < 0 || nextRow > maxRow) return;
      if (nextCol.isOdd != nextRow.isEven) nextCol--;
      if (nextCol < 0) nextCol += 2;
      if (nextCol > maxCol) nextCol -= 2;
    } else {
      nextCol = col + 2 * dCol;
      if (nextCol < 0 || nextCol > maxCol) return;
    }
    _apply(_state.select(_edgeAt(nextRow, nextCol)), persist: false);
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
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) {
      final at = _state.cursor;
      if (at == null) {
        _apply(_state.select(_grid.h(0, 0)), persist: false);
      } else {
        _apply(_state.toggleLine(at));
      }
    } else if (key == LogicalKeyboardKey.keyX) {
      final at = _state.cursor;
      if (at != null) _apply(_state.toggleCross(at));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? _boardMessage(Set<int> satisfied, Set<int> broken, Set<int> branches) {
    if (branches.isNotEmpty) return 'Three lines meet at a dot; the loop cannot branch.';
    if (broken.isNotEmpty) return 'A number can no longer come out right.';
    if (_state.hasLines && satisfied.length == _puzzle.clueCount) {
      return 'Every number is met, but the line is not one closed loop yet.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null;
    final marks = done
        ? List<EdgeMark>.generate(
            _grid.edgeCount,
            (e) => _puzzle.solution[e] ? EdgeMark.line : EdgeMark.empty,
            growable: false,
          )
        : _state.marks;
    final satisfied = done ? const <int>{} : _state.satisfiedCells();
    final broken = done ? const <int>{} : _state.brokenCells();
    final branches = done ? const <int>{} : _state.branchDots();
    final message = done ? null : _boardMessage(satisfied, broken, branches);

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: LoopScreen.help,
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
                        '${satisfied.length} of ${_puzzle.clueCount} numbers met',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LoopBoard(
                      puzzle: _puzzle,
                      marks: marks,
                      satisfied: satisfied,
                      broken: broken,
                      branches: branches,
                      cursor: done ? null : _state.cursor,
                      onTapEdge: done ? null : _tap,
                      onCrossEdge: done ? null : _cross,
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
                      _Action(
                        id: 'mode',
                        icon: _state.crossMode ? Icons.close : Icons.horizontal_rule,
                        label: _state.crossMode ? 'Crosses' : 'Lines',
                        semanticsLabel: _state.crossMode
                            ? 'Marking crosses. Switch to drawing lines.'
                            : 'Drawing lines. Switch to marking crosses.',
                        onPressed: _toggleMode,
                      ),
                      _Action(id: 'undo', icon: Icons.undo, label: 'Undo', onPressed: _state.canUndo ? _undo : null),
                      _Action(id: 'redo', icon: Icons.redo, label: 'Redo', onPressed: _state.canRedo ? _redo : null),
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
  const _Action({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticsLabel,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        key: ValueKey('loop-$id'),
        button: true,
        enabled: onPressed != null,
        label: semanticsLabel ?? label,
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
