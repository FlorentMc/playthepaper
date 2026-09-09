import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/crossmatch/crossmatch.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'crossmatch_board.dart';

/// Crossmatch: nine tiles, and a three-by-three grid whose rows and columns
/// each set a condition. Every tile belongs in one cell only.
class CrossmatchScreen extends StatefulWidget {
  const CrossmatchScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Crossmatch',
    paragraphs: [
      'Each row of the grid sets one condition and each column sets another, so a cell asks for something that meets both. '
          'Nine tiles are shown below the grid, and each one belongs in a single cell.',
      'Tap a tile to pick it up, then tap a cell to put it there. Tap a tile already on the grid to send it back to the tray. '
          'Press and hold a tile to drag it onto a cell instead. Undo takes back your last move.',
      'Check marks any tile that is not where it belongs. You have three checks, and each one is counted in your result.',
      'Press Submit when you are happy. You score a point for each cell holding the right tile, then see the verified grid '
          'with a line on every answer and the sources.',
      'On a keyboard, the arrows move between cells and tiles, Space or Enter picks a tile up and puts it down, Backspace '
          'empties the cell under the cursor, and Escape puts a picked-up tile back.',
      'Most grids hold one or two tiles that honestly suit two cells; the rest of the grid is what pins them down.',
    ],
  );

  @override
  State<CrossmatchScreen> createState() => _CrossmatchScreenState();
}

class _CrossmatchScreenState extends State<CrossmatchScreen> {
  late final CrossmatchPuzzle _puzzle;
  late CrossmatchState _state;
  GameResult? _result;
  bool _completing = false;

  /// The tile the player has picked up, if any.
  int? _selected;

  /// The cursor is on a cell, or on a tray position when [_inTray].
  int _cursor = 0;
  bool _inTray = false;
  bool _keyboardUsed = false;
  final FocusNode _focus = FocusNode(debugLabel: 'crossmatch');

  PlayContext get _play => widget.play;

  static const int _size = CrossmatchPuzzle.size;

  @override
  void initState() {
    super.initState();
    _puzzle = CrossmatchPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    if (_result == null && _state.submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
  }

  CrossmatchState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return CrossmatchState.initial(_puzzle);
    try {
      return CrossmatchState.fromJson(_puzzle, saved);
    } on FormatException {
      return CrossmatchState.initial(_puzzle);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _playing => _result == null && !_completing && !_state.submitted;

  void _apply(CrossmatchState next) {
    if (!_playing || identical(next, _state)) return;
    setState(() => _state = next);
    _play.saveProgress(next.toJson());
  }

  void _place(int tile, int cell) {
    _apply(_state.place(tile, cell));
    setState(() {
      _selected = null;
      _cursor = cell;
      _inTray = false;
    });
  }

  void _tapCell(int cell) {
    _focus.requestFocus();
    if (!_playing) return;
    final picked = _selected;
    if (picked != null) {
      _place(picked, cell);
      return;
    }
    final held = _state.tileAt(cell);
    if (held != null) {
      _apply(_state.clear(cell));
      setState(() {
        _selected = held;
        _cursor = cell;
        _inTray = false;
      });
      return;
    }
    setState(() {
      _cursor = cell;
      _inTray = false;
    });
  }

  void _tapTile(int tile) {
    _focus.requestFocus();
    if (!_playing) return;
    final tray = _state.tray;
    setState(() {
      _selected = _selected == tile ? null : tile;
      final position = tray.indexOf(tile);
      if (position != -1) {
        _cursor = position;
        _inTray = true;
      }
    });
  }

  void _undo() {
    setState(() => _selected = null);
    _apply(_state.undo());
  }

  Future<void> _check() async {
    if (!_playing || !_state.canCheck) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check the grid?'),
        content: Text(
          'Any tile that is not where it belongs is marked. You have ${_state.checksLeft} '
          'check${_state.checksLeft == 1 ? '' : 's'} left, and each one is counted as a hint.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Check')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _selected = null);
    _apply(_state.check());
  }

  Future<void> _submit() async {
    if (!_playing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit this grid?'),
        content: const Text('You score a point for each cell holding the right tile.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_playing) return;
    final next = _state.submit();
    setState(() {
      _state = next;
      _selected = null;
    });
    await _play.saveProgress(next.toJson());
    if (!mounted) return;
    await _complete();
  }

  Future<void> _complete() async {
    if (_completing || _result != null) return;
    _completing = true;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.isSolved,
      points: _state.points,
      maxPoints: CrossmatchPuzzle.cellCount,
      hints: _state.checks,
      shareLines: _state.shareLines(),
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: 'The grid', reveal: _RevealSummary(puzzle: _puzzle));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing || !_focus.hasPrimaryFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final tray = _state.tray;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _keyboardUsed = true;
      if (_inTray) {
        if (_cursor < tray.length) _tapTile(tray[_cursor]);
      } else {
        _tapCell(_cursor);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _selected = null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _keyboardUsed = true;
      if (!_inTray) {
        setState(() => _selected = null);
        _apply(_state.clear(_cursor));
      }
      return KeyEventResult.handled;
    }
    var dx = 0;
    var dy = 0;
    if (key == LogicalKeyboardKey.arrowLeft) {
      dx = -1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      dx = 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      dy = -1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      dy = 1;
    } else {
      return KeyEventResult.ignored;
    }
    _keyboardUsed = true;
    setState(() => _moveCursor(dx, dy, tray.length));
    return KeyEventResult.handled;
  }

  /// Moves over the grid, dropping into the tray below the last row and
  /// climbing back into the bottom row from the tray.
  void _moveCursor(int dx, int dy, int trayLength) {
    if (_inTray) {
      if (dy < 0 || trayLength == 0) {
        _inTray = false;
        _cursor = CrossmatchPuzzle.cellIndex(_size - 1, _cursor.clamp(0, _size - 1));
        return;
      }
      if (dx != 0) _cursor = (_cursor + dx).clamp(0, trayLength - 1);
      return;
    }
    final row = CrossmatchPuzzle.rowOf(_cursor);
    final col = CrossmatchPuzzle.colOf(_cursor);
    if (dy > 0 && row == _size - 1) {
      if (trayLength == 0) return;
      _inTray = true;
      _cursor = col.clamp(0, trayLength - 1);
      return;
    }
    _cursor = CrossmatchPuzzle.cellIndex((row + dy).clamp(0, _size - 1), (col + dx).clamp(0, _size - 1));
  }

  CrossmatchMark _markFor(int cell, {required bool reveal}) {
    if (reveal) return _state.isCorrectAt(cell) ? CrossmatchMark.right : CrossmatchMark.missed;
    return _state.isMarked(cell) ? CrossmatchMark.wrong : CrossmatchMark.none;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final done = result != null || _state.submitted;
    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: CrossmatchScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_puzzle.title != null)
                    Text(_puzzle.title!, style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? 'The verified grid, with a line on every answer.'
                        : 'Put each tile where it meets both conditions.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(child: done ? _buildReveal(context) : _buildPlay(context)),
            if (result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Column(
                  children: [
                    Text(result.summary(), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => _play.showResult(
                        context,
                        result,
                        revealTitle: 'The grid',
                        reveal: _RevealSummary(puzzle: _puzzle),
                      ),
                      child: const Text('See result'),
                    ),
                  ],
                ),
              ),
            if (!done) _buildControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPlay(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGrid(context, reveal: false),
          const SizedBox(height: 12),
          Text('TILES', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          _buildTray(context),
        ],
      ),
    );
  }

  Widget _buildReveal(BuildContext context) {
    final theme = Theme.of(context);
    final sources = _play.record.sources;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
      children: [
        _buildGrid(context, reveal: true),
        const SizedBox(height: 14),
        for (var cell = 0; cell < CrossmatchPuzzle.cellCount; cell++) _buildAnswer(context, cell),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('SOURCES', style: theme.textTheme.labelSmall),
          for (final source in sources) _SourceTile(source: source),
        ],
      ],
    );
  }

  Widget _buildAnswer(BuildContext context, int cell) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final tile = _puzzle.tileAt(cell);
    final right = _state.isCorrectAt(cell);
    final had = _state.tileAt(cell);
    final verdict = right
        ? 'You had this right'
        : had == null
            ? 'You left this cell empty'
            : 'You had ${_puzzle.tiles[had]}';
    return Semantics(
      key: ValueKey('crossmatch-answer-$cell'),
      label: [
        '${_puzzle.rows[CrossmatchPuzzle.rowOf(cell)]}, ${_puzzle.cols[CrossmatchPuzzle.colOf(cell)]}',
        _puzzle.tiles[tile],
        _puzzle.explanations[tile],
        verdict,
      ].join(', '),
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_puzzle.rows[CrossmatchPuzzle.rowOf(cell)]} · ${_puzzle.cols[CrossmatchPuzzle.colOf(cell)]}',
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 2),
              Text(_puzzle.tiles[tile], style: PaperTheme.body(weight: 700)),
              const SizedBox(height: 2),
              Text(_puzzle.explanations[tile], style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(right ? Icons.check : Icons.close, size: 16, color: right ? colors.correct : colors.error),
                  const SizedBox(width: 4),
                  Flexible(child: Text(verdict, style: theme.textTheme.labelSmall)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, {required bool reveal}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 74.0;
        const gap = 4.0;
        final cellWidth = ((constraints.maxWidth - labelWidth - gap * _size) / _size).clamp(56.0, 148.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: labelWidth),
                for (var c = 0; c < _size; c++) ...[
                  const SizedBox(width: gap),
                  CrossmatchLabel(text: _puzzle.cols[c], width: cellWidth, height: 46),
                ],
              ],
            ),
            for (var r = 0; r < _size; r++) ...[
              if (r > 0) const SizedBox(height: gap),
              Row(
                children: [
                  CrossmatchLabel(text: _puzzle.rows[r], width: labelWidth, height: CrossmatchCell.height),
                  for (var c = 0; c < _size; c++) ...[
                    const SizedBox(width: gap),
                    _buildCell(context, CrossmatchPuzzle.cellIndex(r, c), cellWidth, reveal: reveal),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCell(BuildContext context, int cell, double width, {required bool reveal}) {
    final tile = reveal ? _puzzle.tileAt(cell) : _state.tileAt(cell);
    final cursorHere = (_keyboardUsed || _selected != null) && !_inTray && _cursor == cell;
    final widget = CrossmatchCell(
      key: ValueKey('crossmatch-cell-$cell'),
      width: width,
      rowCriterion: _puzzle.rows[CrossmatchPuzzle.rowOf(cell)],
      colCriterion: _puzzle.cols[CrossmatchPuzzle.colOf(cell)],
      text: tile == null ? null : _puzzle.tiles[tile],
      mark: _markFor(cell, reveal: reveal),
      focused: !reveal && cursorHere,
      selected: false,
      onTap: reveal ? null : () => _tapCell(cell),
    );
    if (reveal) return widget;
    final held = _state.tileAt(cell);
    return DragTarget<int>(
      onAcceptWithDetails: (details) => _place(details.data, cell),
      builder: (context, candidate, rejected) {
        if (held == null) return widget;
        return LongPressDraggable<int>(
          data: held,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(text: _puzzle.tiles[held]),
          childWhenDragging: Opacity(opacity: 0.3, child: widget),
          child: widget,
        );
      },
    );
  }

  Widget _buildTray(BuildContext context) {
    final tray = _state.tray;
    if (tray.isEmpty) {
      return Text('Every tile is on the grid.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < tray.length; i++)
          Builder(
            builder: (context) {
              final tile = tray[i];
              final chip = CrossmatchChip(
                key: ValueKey('crossmatch-tile-$tile'),
                text: _puzzle.tiles[tile],
                selected: _selected == tile,
                focused: _keyboardUsed && _inTray && _cursor == i,
                onTap: () => _tapTile(tile),
              );
              return LongPressDraggable<int>(
                data: tile,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: _DragFeedback(text: _puzzle.tiles[tile]),
                childWhenDragging: Opacity(opacity: 0.3, child: chip),
                child: chip,
              );
            },
          ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('crossmatch-undo'),
              onPressed: _state.canUndo ? _undo : null,
              icon: const Icon(Icons.undo, size: 20),
              label: const Text('Undo'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('crossmatch-check'),
              onPressed: _state.canCheck ? _check : null,
              icon: const Icon(Icons.rule, size: 20),
              label: Text('Check ${_state.checksLeft}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('crossmatch-submit'),
              onPressed: _submit,
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tile under the finger while it is being dragged.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: CrossmatchChip(text: text, selected: true, focused: false, onTap: null),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final SourceRef source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“${source.excerpt}”', style: theme.textTheme.bodySmall),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(source.publisher),
            onPressed: () => launchUrl(Uri.parse(source.url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }
}

/// The compact reveal on the result screen: the verified grid, cell by cell.
class _RevealSummary extends StatelessWidget {
  const _RevealSummary({required this.puzzle});

  final CrossmatchPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var cell = 0; cell < CrossmatchPuzzle.cellCount; cell++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${puzzle.rows[CrossmatchPuzzle.rowOf(cell)]} · ${puzzle.cols[CrossmatchPuzzle.colOf(cell)]}',
                  style: theme.textTheme.labelSmall,
                ),
                Text(puzzle.tiles[puzzle.tileAt(cell)], style: PaperTheme.body(weight: 700)),
              ],
            ),
          ),
      ],
    );
  }
}
