import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../../core/game_result.dart';
import '../../core/puzzle_id.dart';
import '../../core/theme.dart';
import '../../shared/widgets/game_shell.dart';
import '../../storage/local_store.dart';
import '../results/share_service.dart';
import 'story_link.dart';

/// Spoiler-free summary of the edition: one line per round, then the link.
String frontPageShareText(EditionManifest m, LocalStore store) {
  final lines = <String>['Daypencil · ${DateFormat('d MMM yyyy').format(m.date.toUtc())}'];
  for (final g in GameKind.newsOrder) {
    final id = m.puzzleFor(g);
    final result = id == null ? null : store.result(id);
    lines.add('${g.title}: ${result?.summary() ?? 'Not played'}');
  }
  lines.add('$kSiteBaseUrl/e/${m.dateString}');
  return lines.join('\n');
}

/// The Front Page: the three stories behind the edition, in newspaper
/// style, with the player's result for each. A story whose puzzle has not
/// been played stays folded until the player chooses to reveal it.
class FrontPageScreen extends StatefulWidget {
  const FrontPageScreen({super.key, required this.dateText});
  final String dateText;

  @override
  State<FrontPageScreen> createState() => _FrontPageScreenState();
}

class _FrontPageScreenState extends State<FrontPageScreen> {
  late Future<EditionManifest> _future;
  final Set<GameKind> _revealed = {};

  @override
  void initState() {
    super.initState();
    final date = parseRouteDate(widget.dateText);
    final repo = context.read<ContentRepository>();
    _future = date == null ? Future.error(const ContentNotFound('date')) : repo.edition(date);
  }

  Future<void> _share(EditionManifest m, LocalStore store) async {
    final ok = await ShareService.share(frontPageShareText(m, store), subject: 'Daypencil');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Edition shared' : 'Could not share')));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('The Front Page'),
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
            final dateLabel = DateFormat('EEEE d MMMM yyyy').format(m.date.toUtc());
            final unplayed = GameKind.newsOrder.where((g) {
              final id = m.puzzleFor(g);
              return id != null && !store.isCompleted(id) && !_revealed.contains(g);
            }).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  'The Front Page',
                  style: DaypencilTheme.display(size: 32, color: theme.colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(dateLabel.toUpperCase(), style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
                Text(m.label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Rule(thick: true),
                if (unplayed.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Reveal all'),
                      onPressed: () => setState(() => _revealed.addAll(unplayed)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                for (var i = 0; i < GameKind.newsOrder.length; i++) ...[
                  _StoryCard(
                    index: i + 1,
                    game: GameKind.newsOrder[i],
                    story: m.storyFor(GameKind.newsOrder[i]),
                    puzzleId: m.puzzleFor(GameKind.newsOrder[i]),
                    revealed: _revealed.contains(GameKind.newsOrder[i]),
                    onReveal: () => setState(() => _revealed.add(GameKind.newsOrder[i])),
                  ),
                  const SizedBox(height: 14),
                ],
                const Rule(),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share the edition'),
                  onPressed: () => _share(m, store),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.go('/'), child: const Text('Back to today')),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.index,
    required this.game,
    required this.story,
    required this.puzzleId,
    required this.revealed,
    required this.onReveal,
  });

  final int index;
  final GameKind game;
  final Story? story;
  final PuzzleId? puzzleId;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final GameResult? result = puzzleId == null ? null : store.result(puzzleId!);
    final label = 'STORY $index · ${game.title.toUpperCase()}';

    if (story == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text('Story $index · not available', style: theme.textTheme.titleMedium),
        ),
      );
    }

    if (result == null && !revealed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: 4),
              Text('Story $index · not played yet', style: DaypencilTheme.display(size: 20, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 6),
              Text('Play ${game.title} first, or reveal the story now.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(onPressed: onReveal, child: const Text('Reveal')),
                  const SizedBox(width: 10),
                  if (puzzleId != null)
                    FilledButton(onPressed: () => context.push('/p/$puzzleId'), child: Text('Play ${game.title}')),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(story!.headline, style: DaypencilTheme.display(size: 22, color: theme.colorScheme.onSurface, height: 1.2)),
            const SizedBox(height: 10),
            Text(story!.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            StoryLink(url: story!.url, publisher: story!.publisher),
            const Rule(),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  result == null
                      ? Icons.circle_outlined
                      : result.solved
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                  size: 18,
                  color: result == null
                      ? theme.colorScheme.outline
                      : result.solved
                          ? colors.correct
                          : colors.subtle,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result == null ? 'Not played' : 'You: ${result.summary()}',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (result == null && puzzleId != null)
                  TextButton(onPressed: () => context.push('/p/$puzzleId'), child: const Text('Play')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
