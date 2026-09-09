import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/game_result.dart';
import '../../../core/theme.dart';
import '../../../engines/groups/groups.dart';
import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';
import 'groups_board.dart';

/// Groups: twelve words that sort into three groups of four.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Groups',
    paragraphs: [
      'Twelve words belong to three groups of four. Tap four that go together, then press Submit.',
      'A right answer locks the group at the top with its title and a sentence saying why. A wrong one costs a mistake, '
          'and you are told when you were one word away. Four mistakes end the game and the groups are shown.',
      'One word in each puzzle sits comfortably in two of the groups. Only one arrangement fills all three, so when a '
          'group looks full without a word, that word belongs somewhere else.',
      'Shuffle reorders the words still in play; it never changes the answer. Everyone playing on the same day sees the '
          'same board.',
      'On a keyboard, the arrows move the outline from word to word, Space picks a word up or puts it down, and Enter '
          'submits your four.',
    ],
  );

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final GroupsPuzzle _puzzle;
  late GroupsState _state;
  GameResult? _result;
  bool _completing = false;
  int _cursor = 0;
  bool _keyboardUsed = false;
  final FocusNode _focus = FocusNode(debugLabel: 'groups');

  PlayContext get _play => widget.play;

  @override
  void initState() {
    super.initState();
    _puzzle = GroupsPuzzle.parse(_play.record.payload, _play.record.reveal);
    _state = _restore();
    _result = _play.existingResult();
    if (_result == null && _state.isOver) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    }
  }

  GroupsState _restore() {
    final saved = _play.loadProgress();
    if (saved == null) return GroupsState.initial(_puzzle);
    try {
      return GroupsState.fromJson(_puzzle, saved);
    } on FormatException {
      return GroupsState.initial(_puzzle);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _playing => _result == null && !_completing && !_state.isOver;

  void _apply(GroupsState next) {
    if (!_playing || identical(next, _state)) return;
    setState(() {
      _state = next;
      if (_cursor >= next.remaining.length) _cursor = next.remaining.isEmpty ? 0 : next.remaining.length - 1;
    });
    _play.saveProgress(next.toJson());
  }

  void _tapTile(String tile) {
    _focus.requestFocus();
    final at = _state.remaining.indexOf(tile);
    if (at >= 0) setState(() => _cursor = at);
    _apply(_state.toggle(tile));
  }

  void _shuffle() => _apply(_state.shuffle());

  void _clear() => _apply(_state.clearSelection());

  Future<void> _submit() async {
    if (!_state.canSubmit) return;
    final next = _state.submit();
    _apply(next);
    if (next.isOver) await _complete();
  }

  Future<void> _complete() async {
    if (_completing || _result != null) return;
    _completing = true;
    final result = GameResult(
      puzzleId: _play.record.id,
      completedAt: DateTime.now().toUtc(),
      solved: _state.isSolved,
      attempts: _state.mistakes,
      shareLines: _state.shareLines(),
      note: _state.note(),
      isArchivePlay: _play.isArchivePlay,
    );
    setState(() => _result = result);
    await _play.complete(context, result, revealTitle: 'The groups', reveal: _RevealSummary(puzzle: _puzzle));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_playing || !_focus.hasPrimaryFocus || _state.remaining.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _keyboardUsed = true;
      _apply(_state.toggle(_state.remaining[_cursor]));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _keyboardUsed = true;
      _submit();
      return KeyEventResult.handled;
    }
    final int delta;
    if (key == LogicalKeyboardKey.arrowLeft) {
      delta = -1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      delta = 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -GroupsPuzzle.columns;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      delta = GroupsPuzzle.columns;
    } else {
      return KeyEventResult.ignored;
    }
    _keyboardUsed = true;
    setState(() => _cursor = (_cursor + delta).clamp(0, _state.remaining.length - 1));
    return KeyEventResult.handled;
  }

  String? _message() {
    switch (_state.lastOutcome) {
      case GroupsOutcome.correct:
        return _state.isSolved ? 'All three groups found.' : 'That is a group.';
      case GroupsOutcome.oneAway:
        return 'One away. Three of those belong together.';
      case GroupsOutcome.wrong:
        return 'Not a group. That costs a mistake.';
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final over = result != null || _state.isOver;
    final reviewing = result != null && !_state.isOver;
    final shown = over
        ? [for (var i = 0; i < GroupsPuzzle.groupCount; i++) i]
        : _state.found;

    return GameShell(
      game: _play.record.game,
      date: _play.record.date,
      difficulty: _play.record.difficulty,
      help: GroupsScreen.help,
      isArchivePlay: _play.isArchivePlay,
      puzzleId: _play.record.id.toString(),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                children: [
                  if (!over)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Find the three groups of four. Tap four words, then Submit.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  for (final index in shown)
                    GroupsBand(
                      group: _puzzle.groups[index],
                      index: index,
                      found: reviewing || _state.found.contains(index),
                    ),
                  if (!over) _buildGrid(context),
                  if (over) ...[
                    const SizedBox(height: 4),
                    Text(
                      reviewing
                          ? 'The three groups in this puzzle.'
                          : _state.isSolved
                              ? 'All three groups found.'
                              : 'The game ended after four mistakes; here are the groups.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_play.record.sources.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('SOURCES', style: theme.textTheme.labelSmall),
                      for (final source in _play.record.sources) _SourceTile(source: source),
                    ],
                  ],
                ],
              ),
            ),
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
                        revealTitle: 'The groups',
                        reveal: _RevealSummary(puzzle: _puzzle),
                      ),
                      child: const Text('See result'),
                    ),
                  ],
                ),
              )
            else if (!over)
              _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final tiles = _state.remaining;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: GroupsPuzzle.columns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        mainAxisExtent: 64,
      ),
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return GroupsTile(
          key: ValueKey('groups-tile-${GroupsPuzzle.normalise(tile)}'),
          text: tile,
          selected: _state.isSelected(tile),
          focused: _keyboardUsed && _cursor == index,
          position: index + 1,
          count: tiles.length,
          onTap: () => _tapTile(tile),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final message = _message();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 24,
            child: message == null
                ? null
                : Text(message, style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
          ),
          Semantics(
            label: 'Mistakes ${_state.mistakes} of ${GroupsState.maxMistakes}',
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Mistakes ${_state.mistakes} of ${GroupsState.maxMistakes}', style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                for (var i = 0; i < GroupsState.maxMistakes; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      i < _state.mistakes ? Icons.close : Icons.circle_outlined,
                      size: 14,
                      color: i < _state.mistakes ? colors.error : colors.subtle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('groups-shuffle'),
                  onPressed: _state.canShuffle ? _shuffle : null,
                  child: const Text('Shuffle'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('groups-clear'),
                  onPressed: _state.selected.isEmpty ? null : _clear,
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('groups-submit'),
                  onPressed: _state.canSubmit ? _submit : null,
                  child: const Text('Submit'),
                ),
              ),
            ],
          ),
        ],
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

/// The compact reveal on the result screen: each group, its words and why.
class _RevealSummary extends StatelessWidget {
  const _RevealSummary({required this.puzzle});

  final GroupsPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < puzzle.groups.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${GroupsState.markFor(i)} ${puzzle.groups[i].title}', style: PaperTheme.body(weight: 700)),
                Text(puzzle.groups[i].members.join(' · '), style: theme.textTheme.bodyMedium),
                Text(puzzle.groups[i].explanation, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
