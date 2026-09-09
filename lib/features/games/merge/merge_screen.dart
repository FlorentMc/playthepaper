import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/game_kind.dart';
import '../../../core/game_result.dart';
import '../../../engines/merge/merge.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'merge_board.dart';
import 'merge_controls.dart';
import 'merge_extras.dart';

enum _Mode { daily, unlimited }

/// 2048: slide the board, merge equal tiles, chase the big one. The daily
/// challenge deals from the puzzle's seed so everyone plays the same game;
/// Unlimited is free play kept in local extras and never recorded.
class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: '2048',
    paragraphs: [
      'Swipe the board, or press the arrow buttons, to slide every tile as far as it will go. '
          'Two tiles showing the same number merge into their sum, and a tile that has just merged does not '
          'merge again on the same slide. Your score is everything you have merged.',
      'A slide that moves nothing changes nothing. After every slide that does move something, a new 2 appears '
          'in a free square, or a 4 about one time in ten.',
      'The daily board and the whole order of new tiles come from the day\'s puzzle, so everyone plays the same '
          'game. Each day is checked before it is published: a reference player that always slides left, then up, '
          'must last 200 slides and reach a 256 tile, so no day starts on a board that dies in a minute. '
          'Reaching 2048 is the win, and you may stop there or play on for a bigger tile.',
      'Undo takes back one slide, new tile and all. It is there for a slip, and it counts as a hint on your result. '
          'The day ends when no slide would change the board, or when you press Finish.',
      'Unlimited is the same game with nothing recorded: a fresh deal whenever you want one, and your best '
          'free-play score remembered.',
      'On a keyboard, the arrow keys or W, A, S and D slide the board. Every tile is labelled with its number, '
          'so you never need the colours to read it.',
    ],
  );

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  late final MergePuzzle _puzzle;
  late MergeExtras _extras;
  late MergeState _daily;
  MergeState? _unlimited;
  MergeState? _review;
  _Mode _mode = _Mode.daily;
  GameResult? _result;
  bool _completing = false;
  double _dragX = 0;
  double _dragY = 0;
  final FocusNode _focus = FocusNode(debugLabel: 'merge');

  PlayContext get _play => widget.play;

  bool get _isDaily => _mode == _Mode.daily;

  MergeState get _current => _isDaily ? _daily : _unlimited!;

  bool get _canPlay => !_current.isOver && !(_isDaily && (_result != null || _completing));

  @override
  void initState() {
    super.initState();
    _puzzle = MergePuzzle.parse(_play.record.payload, _play.record.reveal);
    _extras = MergeExtras.load(_play.store);
    _result = _play.existingResult();
    _daily = _restoreDaily();
    _unlimited = _extras.unlimitedState();
    if (_result != null) _review = _extras.finishedState(_play.record.id.toString());
    if (_result == null && _daily.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeDaily());
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  MergeState _restoreDaily() {
    final saved = _play.loadProgress();
    if (saved == null) return MergeState.of(_puzzle);
    try {
      final state = MergeState.fromJson(saved);
      if (state.seed != _puzzle.seed || state.size != _puzzle.size) return MergeState.of(_puzzle);
      return state;
    } on FormatException {
      return MergeState.of(_puzzle);
    }
  }

  void _set(MergeState state) {
    if (_isDaily) {
      _daily = state;
    } else {
      _unlimited = state;
    }
  }

  Future<void> _persist(MergeState state) async {
    if (_isDaily) {
      await _play.saveProgress(state.toJson());
    } else {
      _extras = _extras.withUnlimited(state);
      await _extras.save(_play.store);
    }
  }

  Future<void> _push(MergeDirection direction) async {
    if (!_canPlay) return;
    final current = _current;
    final next = current.move(direction);
    if (identical(next, current)) return;
    setState(() => _set(next));
    await _persist(next);
    if (!mounted) return;
    if (next.awaitsChoice) {
      await _askChoice();
      if (!mounted) return;
    }
    if (_current.isStuck && !_current.finished) await _endGame();
  }

  Future<void> _undo() async {
    if (!_isDaily || !_canPlay || !_daily.canUndo) return;
    final next = _daily.undo();
    setState(() => _daily = next);
    await _persist(next);
  }

  Future<void> _askChoice() async {
    final daily = _isDaily;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('2048 made'),
        content: Text(
          daily
              ? 'You have built the tile. Finish here and record your score, or play on for a bigger one.'
              : 'You have built the tile. Play on for a bigger one, or start again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(daily ? 'Finish' : 'New game'),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep going')),
        ],
      ),
    );
    if (!mounted) return;
    if (stop == true) {
      if (daily) {
        await _completeDaily();
      } else {
        await _newUnlimited();
      }
      return;
    }
    final next = _current.keepPlaying();
    setState(() => _set(next));
    await _persist(next);
  }

  Future<void> _endGame() async {
    if (_isDaily) {
      await _completeDaily();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _finishDaily() async {
    if (!_isDaily || !_canPlay) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish today?'),
        content: const Text('Your score is recorded as it stands and the board is closed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Finish')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _completeDaily();
  }

  Future<void> _completeDaily() async {
    if (_result != null || _completing) return;
    _completing = true;
    final state = _daily.finish();
    _extras = _extras.withFinished(_play.record.id.toString(), state);
    await _extras.save(_play.store);
    if (!mounted) return;
    final score = MergeRules.groupDigits(state.score);
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: state.isSolved,
      points: state.score,
      hints: state.undosUsed,
      shareLines: ['🔢 $score · ${state.bestTile}'],
      isArchivePlay: _play.isArchivePlay,
      note: 'Score $score · best tile ${state.bestTile}',
    );
    setState(() {
      _daily = state;
      _review = state;
      _result = result;
    });
    await _play.complete(context, result, revealTitle: 'Your board', reveal: _reviewCard(state));
  }

  Future<void> _newUnlimited() async {
    final state = _dealUnlimited();
    setState(() => _unlimited = state);
    _extras = _extras.withUnlimited(state);
    await _extras.save(_play.store);
  }

  Future<void> _confirmNewUnlimited() async {
    final current = _unlimited;
    if (current != null && current.moves > 0 && !current.isOver) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start again?'),
          content: const Text('This game goes, and a new board is dealt.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('New game')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _newUnlimited();
  }

  void _setMode(_Mode mode) {
    if (mode == _mode) return;
    final dealing = mode == _Mode.unlimited && _unlimited == null;
    if (dealing) _unlimited = _dealUnlimited();
    setState(() => _mode = mode);
    if (dealing) _persist(_unlimited!);
    _focus.requestFocus();
  }

  MergeState _dealUnlimited() => MergeState.start(
        seed: MergeRandom.normalise(DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF),
        size: _puzzle.size,
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_canPlay) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => MergeDirection.left,
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD => MergeDirection.right,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => MergeDirection.up,
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => MergeDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    _push(direction);
    return KeyEventResult.handled;
  }

  int get _bestScore {
    if (!_isDaily) return _extras.bestUnlimited;
    var best = 0;
    for (final r in _play.store.resultsFor(GameKind.merge)) {
      final points = r.points ?? 0;
      if (points > best) best = points;
    }
    return best;
  }

  String? _statusLine(MergeState state) {
    if (state.isStuck) return 'No moves left.';
    if (state.isSolved) return state.keepGoing ? '2048 made. Playing on.' : '2048 made.';
    if (state.emptyCount == 1) return 'One square left.';
    return null;
  }

  Widget _reviewCard(MergeState state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: AspectRatio(aspectRatio: 1, child: MergeBoard(state: state, markSpawn: false)),
          ),
          const SizedBox(height: 10),
          Text(
            '${state.moves} slide${state.moves == 1 ? '' : 's'}'
            '${state.undosUsed == 0 ? '' : ', ${state.undosUsed} taken back'}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );

  Widget _board(MergeState state, {required bool live}) {
    final board = Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AspectRatio(aspectRatio: 1, child: MergeBoard(state: state, markSpawn: live)),
      ),
    );
    if (!live) return board;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragX = 0,
      onHorizontalDragUpdate: (d) => _dragX += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        if (_dragX.abs() < 16 && velocity.abs() < 100) return;
        final amount = _dragX.abs() < 16 ? velocity : _dragX;
        _push(amount < 0 ? MergeDirection.left : MergeDirection.right);
      },
      onVerticalDragStart: (_) => _dragY = 0,
      onVerticalDragUpdate: (d) => _dragY += d.delta.dy,
      onVerticalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        if (_dragY.abs() < 16 && velocity.abs() < 100) return;
        final amount = _dragY.abs() < 16 ? velocity : _dragY;
        _push(amount < 0 ? MergeDirection.up : MergeDirection.down);
      },
      child: board,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final finished = _isDaily && result != null;
    final shown = finished ? _review : _current;
    final status = finished || shown == null ? null : _statusLine(shown);

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: MergeScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: () => _focus.requestFocus(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.daily, label: Text('Daily'), icon: Icon(Icons.today_outlined)),
                    ButtonSegment(value: _Mode.unlimited, label: Text('Unlimited'), icon: Icon(Icons.all_inclusive)),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setMode(s.first),
                  style: SegmentedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    selectedForegroundColor: theme.colorScheme.surface,
                    selectedBackgroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: theme.colorScheme.onSurface),
                    minimumSize: const Size(48, 48),
                    textStyle: theme.textTheme.labelLarge,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: MergeScores(
                  score: shown?.score ?? result?.points ?? 0,
                  bestTile: shown?.bestTile ?? 0,
                  best: _bestScore,
                  bestLabel: _isDaily ? 'Best daily' : 'Best free',
                ),
              ),
              Expanded(
                child: shown == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Today\'s game is finished. The board is no longer kept, but your result is.',
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _board(shown, live: !finished),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(status, style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
                ),
              if (finished)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: Column(
                    children: [
                      Text(result.summary(), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () => _play.showResult(
                          context,
                          result,
                          revealTitle: _review == null ? null : 'Your board',
                          reveal: _review == null ? null : _reviewCard(_review!),
                        ),
                        child: const Text('See result'),
                      ),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: MergeArrows(onMove: _push, enabled: _canPlay),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Row(
                    children: [
                      if (_isDaily) ...[
                        MergeAction(
                          id: 'undo',
                          icon: Icons.undo,
                          label: 'Undo',
                          badge: _daily.undosUsed == 0 ? null : '(${_daily.undosUsed})',
                          onPressed: _daily.canUndo && _canPlay ? _undo : null,
                        ),
                        MergeAction(
                          id: 'finish',
                          icon: Icons.flag_outlined,
                          label: 'Finish',
                          onPressed: _canPlay ? _finishDaily : null,
                        ),
                      ] else
                        MergeAction(
                          id: 'new',
                          icon: Icons.refresh,
                          label: 'New game',
                          onPressed: _confirmNewUnlimited,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
