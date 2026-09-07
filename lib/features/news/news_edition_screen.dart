import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../../core/theme.dart';
import '../../shared/widgets/game_shell.dart';
import '../../storage/local_store.dart';
import '../play/game_registry.dart';
import '../play/play_screen.dart';

/// The news edition flow: Correct, The Number, Where, then the Front Page.
/// Players can leave after any round; progress is read from the store.
class NewsEditionScreen extends StatefulWidget {
  const NewsEditionScreen({super.key, required this.dateText});
  final String dateText;

  @override
  State<NewsEditionScreen> createState() => _NewsEditionScreenState();
}

class _NewsEditionScreenState extends State<NewsEditionScreen> {
  late Future<EditionManifest> _future;

  @override
  void initState() {
    super.initState();
    final date = parseRouteDate(widget.dateText);
    final repo = context.read<ContentRepository>();
    _future = date == null ? Future.error(const ContentNotFound('date')) : repo.edition(date);
  }

  GameKind? _nextRound(EditionManifest m, LocalStore store) {
    for (final g in GameKind.newsOrder) {
      final id = m.puzzleFor(g);
      if (id != null && !store.isCompleted(id)) return g;
    }
    return null;
  }

  void _openRound(EditionManifest m, GameKind game) {
    final id = m.puzzleFor(game)!;
    final idx = GameKind.newsOrder.indexOf(game);
    final following = idx + 1 < GameKind.newsOrder.length ? GameKind.newsOrder[idx + 1] : null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayScreen(
          puzzleIdText: id.toString(),
          nextLabel: following == null ? 'Read the Front Page' : 'Next: ${following.title}',
          onNext: () {
            // Pop the result screen and the game, then open what follows.
            Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == 'news-flow');
            if (following == null) {
              context.push('/front/${m.dateString}');
            } else {
              _openRound(m, following);
            }
          },
        ),
        settings: const RouteSettings(name: 'news-round'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('The edition'),
      ),
      body: SafeArea(
        child: FutureBuilder<EditionManifest>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('No edition for ${widget.dateText}.', style: theme.textTheme.titleMedium));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final m = snap.data!;
            final next = _nextRound(m, store);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Text(
                  m.kind == EditionKind.evergreen ? m.label : 'Three stories from today',
                  style: DaypencilTheme.display(size: 24, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  m.kind == EditionKind.evergreen
                      ? 'A prepared edition. The stories are true, but not from today\'s news.'
                      : 'Each round covers a different story. Play them in order; leave whenever you like.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                const Rule(thick: true),
                const SizedBox(height: 8),
                for (final g in GameKind.newsOrder) ...[
                  _RoundTile(
                    game: g,
                    manifest: m,
                    isNext: g == next,
                    onTap: () => _openRound(m, g),
                  ),
                  const Rule(),
                ],
                const SizedBox(height: 20),
                if (next == null)
                  FilledButton.icon(
                    icon: const Icon(Icons.newspaper),
                    label: const Text('Read the Front Page'),
                    onPressed: () => context.push('/front/${m.dateString}'),
                  )
                else ...[
                  FilledButton(onPressed: () => _openRound(m, next), child: Text('Play ${next.title}')),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.push('/front/${m.dateString}'),
                    child: const Text('Finish early and reveal the Front Page'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  const _RoundTile({required this.game, required this.manifest, required this.isNext, required this.onTap});
  final GameKind game;
  final EditionManifest manifest;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final id = manifest.puzzleFor(game);
    final result = id == null ? null : store.result(id);
    final inProgress = id != null && store.hasProgress(id);
    final n = GameKind.newsOrder.indexOf(game) + 1;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: CircleAvatar(
        backgroundColor: result != null ? colors.correct : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: result != null ? colors.onFeedback : theme.colorScheme.onSurface,
        child: result != null ? const Icon(Icons.check) : Text('$n'),
      ),
      title: Text(game.title, style: DaypencilTheme.display(size: 18, color: theme.colorScheme.onSurface)),
      subtitle: Text(
        result != null
            ? result.summary()
            : inProgress
                ? 'In progress'
                : GameRegistry.blurbs[game]!,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Icon(isNext ? Icons.play_arrow : Icons.chevron_right),
      onTap: id == null ? null : onTap,
    );
  }
}
