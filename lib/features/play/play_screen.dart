import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/game_result.dart';
import '../../core/puzzle_id.dart';
import '../../storage/local_store.dart';
import 'game_registry.dart';
import 'play_context.dart';

/// Opens any puzzle by its permanent id. This is the target of every shared
/// link, so it must work with nothing but the id: it fetches the puzzle,
/// then its edition for the story, and builds the play context.
class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.puzzleIdText,
    this.challengeCode,
    this.nextLabel,
    this.onNext,
    this.onCompleted,
  });

  final String puzzleIdText;
  final String? challengeCode;
  final String? nextLabel;
  final VoidCallback? onNext;
  final void Function(GameResult)? onCompleted;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _LoadedPlay {
  _LoadedPlay(this.record, this.story);
  final PuzzleRecord record;
  final Story? story;
}

class _PlayScreenState extends State<PlayScreen> {
  late Future<_LoadedPlay> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoadedPlay> _load() async {
    final id = PuzzleId.tryParse(widget.puzzleIdText);
    if (id == null) throw ContentNotFound('puzzle ${widget.puzzleIdText}');
    final repo = context.read<ContentRepository>();
    final record = await repo.puzzle(id);
    Story? story;
    if (id.game.isNews) {
      try {
        final edition = await repo.edition(id.date);
        story = edition.stories.where((s) => s.id == record.storyId).firstOrNull ?? edition.storyFor(id.game);
      } on ContentNotFound {
        story = null;
      }
    }
    return _LoadedPlay(record, story);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedPlay>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
              ),
              title: const Text('Puzzle'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('This puzzle could not be loaded.', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'It may need a connection the first time, or the link may be wrong.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => setState(() => _future = _load()), child: const Text('Try again')),
                    TextButton(onPressed: () => context.go('/'), child: const Text('Back to today')),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final loaded = snap.data!;
        final store = context.read<LocalStore>();
        final editions = context.read<EditionController>();
        final id = loaded.record.id;
        final challenge = widget.challengeCode == null ? null : GameResult.fromChallengeCode(id, widget.challengeCode!);
        final play = PlayContext(
          store: store,
          record: loaded.record,
          story: loaded.story,
          challenge: challenge,
          isArchivePlay: id.date.isBefore(editions.todayDate),
          nextLabel: widget.nextLabel,
          onNext: widget.onNext,
          onCompleted: widget.onCompleted,
        );
        return GameRegistry.screens[id.game]!(context, play);
      },
    );
  }
}
