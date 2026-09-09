import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import '../../core/theme.dart';
import '../../shared/widgets/game_shell.dart';
import '../../storage/local_store.dart';
import '../play/game_registry.dart';

/// The body of the home page and of any archived edition page: the masthead
/// date, the news edition card, then the four classics.
class EditionView extends StatelessWidget {
  const EditionView({super.key, required this.manifest, required this.isToday});

  final EditionManifest manifest;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE d MMMM yyyy').format(manifest.date.toUtc());

    final classics = GameKind.classics.toList()
      ..sort((a, b) {
        final fa = store.favourites.contains(a) ? 0 : 1;
        final fb = store.favourites.contains(b) ? 0 : 1;
        return fa != fb ? fa.compareTo(fb) : GameKind.values.indexOf(a).compareTo(GameKind.values.indexOf(b));
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Text(dateLabel.toUpperCase(), style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          isToday
              ? 'Today'
              : manifest.date.isAfter(context.read<EditionController>().todayDate)
                  ? 'Coming up'
                  : 'From the archive',
          style: PaperTheme.display(size: 16, weight: 400, color: theme.colorScheme.onSurface),
          textAlign: TextAlign.center,
        ),
        if (manifest.correctionNote != null) ...[
          const SizedBox(height: 8),
          Text('Correction: ${manifest.correctionNote}', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 14),
        const Rule(thick: true),
        const SizedBox(height: 14),
        _NewsCard(manifest: manifest, isToday: isToday),
        const SizedBox(height: 22),
        Text('THE CLASSICS', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        const Rule(),
        const SizedBox(height: 12),
        for (final game in classics) ...[
          _ClassicCard(manifest: manifest, game: game, isToday: isToday),
          const SizedBox(height: 12),
        ],
        for (final category in [GameCategory.logic, GameCategory.play, GameCategory.editorial])
          if (manifest.games.any((g) => g.category == category)) ...[
            const SizedBox(height: 10),
            Text(category.title.toUpperCase(), style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            const Rule(),
            const SizedBox(height: 12),
            _TileGrid(
              manifest: manifest,
              games: manifest.games.where((g) => g.category == category).toList(),
              favourites: store.favourites,
            ),
          ],
      ],
    );
  }
}

/// Two-column grid of compact tiles for the optional games, so the page
/// stays scannable as the collection grows.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.manifest, required this.games, required this.favourites});
  final EditionManifest manifest;
  final List<GameKind> games;
  final Set<GameKind> favourites;

  @override
  Widget build(BuildContext context) {
    final ordered = games.toList()
      ..sort((a, b) {
        final fa = favourites.contains(a) ? 0 : 1;
        final fb = favourites.contains(b) ? 0 : 1;
        return fa != fb ? fa.compareTo(fb) : GameKind.values.indexOf(a).compareTo(GameKind.values.indexOf(b));
      });
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 3 : 2;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final g in ordered)
              SizedBox(width: width, child: _CompactTile(manifest: manifest, game: g, pinned: favourites.contains(g))),
          ],
        );
      },
    );
  }
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({required this.manifest, required this.game, required this.pinned});
  final EditionManifest manifest;
  final GameKind game;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final id = manifest.puzzleFor(game);
    final result = id == null ? null : store.result(id);
    final inProgress = id != null && store.hasProgress(id);
    final IconData icon;
    final Color iconColor;
    final String status;
    if (result != null) {
      icon = Icons.check_circle;
      iconColor = colors.correct;
      status = result.summary();
    } else if (inProgress) {
      icon = Icons.pause_circle_outline;
      iconColor = colors.misplaced;
      status = 'In progress';
    } else {
      icon = Icons.circle_outlined;
      iconColor = theme.colorScheme.outline;
      status = GameRegistry.blurbs[game] ?? '';
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: id == null ? null : () => context.push('/p/$id'),
        onLongPress: () => store.toggleFavourite(game),
        child: Semantics(
          button: true,
          label: '${game.title}. $status. Long press to ${pinned ? 'unpin' : 'pin'}.',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        game.title,
                        style: PaperTheme.display(size: 17, color: theme.colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (pinned) Icon(Icons.push_pin, size: 14, color: colors.subtle),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(icon, size: 15, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(status, style: theme.textTheme.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.manifest, required this.isToday});
  final EditionManifest manifest;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final quiz = manifest.puzzleFor(GameKind.quiz);
    final result = quiz == null ? null : store.result(quiz);
    final inProgress = quiz != null && store.hasProgress(quiz);
    final kindLabel = manifest.kind == EditionKind.evergreen ? 'Evergreen edition' : 'Today\'s edition';

    final String action;
    if (quiz == null) {
      action = 'Not available';
    } else if (result != null) {
      action = 'Read the Front Page';
    } else if (inProgress) {
      action = 'Continue the quiz';
    } else {
      action = 'Start the quiz';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: quiz == null
            ? null
            : () => result != null
                ? context.push('/front/${manifest.dateString}')
                : context.push('/news/${manifest.dateString}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(kindLabel.toUpperCase(), style: theme.textTheme.labelSmall)),
                  if (result != null) Text(result.summary(), style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                manifest.kind == EditionKind.evergreen ? manifest.label : 'The Quiz',
                style: PaperTheme.display(size: 22, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Five questions from ${manifest.stories.length} stories, one wager. '
                'The same stories seed today\'s word, letters and crossword.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < manifest.stories.length; i++) ...[
                    Icon(
                      result != null ? Icons.check_circle : Icons.circle_outlined,
                      size: 14,
                      color: result != null ? colors.correct : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      result != null ? 'Stories unlocked' : '${manifest.stories.length} stories to unlock',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Text(action, style: theme.textTheme.labelLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassicCard extends StatelessWidget {
  const _ClassicCard({required this.manifest, required this.game, required this.isToday});
  final EditionManifest manifest;
  final GameKind game;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final pinned = store.favourites.contains(game);

    if (game == GameKind.sudoku) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(game: game, pinned: pinned, onPin: () => store.toggleFavourite(game)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in Difficulty.values)
                    _DifficultyChip(id: manifest.puzzleFor(game, difficulty: d), difficulty: d),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final id = manifest.puzzleFor(game);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: id == null ? null : () => context.push('/p/$id'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(game: game, pinned: pinned, onPin: () => store.toggleFavourite(game)),
              const SizedBox(height: 4),
              Text(GameRegistry.blurbs[game]!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              _StatusLine(id: id),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.game, required this.pinned, required this.onPin});
  final GameKind game;
  final bool pinned;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(game.title, style: PaperTheme.display(size: 20, color: theme.colorScheme.onSurface))),
        IconButton(
          icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
          tooltip: pinned ? 'Unpin' : 'Pin to top',
          onPressed: onPin,
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.id});
  final PuzzleId? id;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final theme = Theme.of(context);
    final colors = context.gameColors;
    if (id == null) return Text('Not available', style: theme.textTheme.labelSmall);
    final result = store.result(id!);
    if (result != null) {
      return Row(children: [
        Icon(Icons.check_circle, size: 16, color: colors.correct),
        const SizedBox(width: 6),
        Text(result.summary(), style: theme.textTheme.labelMedium),
      ]);
    }
    if (store.hasProgress(id!)) {
      return Row(children: [
        Icon(Icons.pause_circle_outline, size: 16, color: colors.misplaced),
        const SizedBox(width: 6),
        Text('In progress · tap to resume', style: theme.textTheme.labelMedium),
      ]);
    }
    return Text('Play', style: theme.textTheme.labelLarge);
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.id, required this.difficulty});
  final PuzzleId? id;
  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final colors = context.gameColors;
    final done = id != null && store.isCompleted(id!);
    final inProgress = id != null && store.hasProgress(id!);
    return ActionChip(
      avatar: done
          ? Icon(Icons.check, size: 16, color: colors.correct)
          : inProgress
              ? Icon(Icons.pause, size: 16, color: colors.misplaced)
              : null,
      label: Text(difficulty.label),
      onPressed: id == null ? null : () => context.push('/p/$id'),
    );
  }
}
