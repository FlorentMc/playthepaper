import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
          isToday ? 'Today' : 'From the archive',
          style: DaypencilTheme.display(size: 16, weight: 400, color: theme.colorScheme.onSurface),
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
      ],
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
    final rounds = GameKind.newsOrder.map((g) => manifest.puzzleFor(g)).toList();
    final done = rounds.where((id) => id != null && store.isCompleted(id)).length;
    final started = rounds.any((id) => id != null && (store.isCompleted(id) || store.hasProgress(id)));
    final available = rounds.every((id) => id != null);
    final kindLabel = manifest.kind == EditionKind.evergreen ? 'Evergreen edition' : 'News edition';

    final String action;
    if (!available) {
      action = 'Not available';
    } else if (done == rounds.length) {
      action = 'Read the Front Page';
    } else if (started) {
      action = 'Continue the edition';
    } else {
      action = 'Start the edition';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: !available
            ? null
            : () => done == rounds.length
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
                  Text('$done / ${rounds.length}', style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                manifest.kind == EditionKind.evergreen ? manifest.label : 'Three stories, three rounds',
                style: DaypencilTheme.display(size: 22, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Correct · The Number · Where · Front Page. About four minutes.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < rounds.length; i++) ...[
                    _RoundDot(
                      label: GameKind.newsOrder[i].title,
                      done: rounds[i] != null && store.isCompleted(rounds[i]!),
                      color: colors.correct,
                    ),
                    if (i < rounds.length - 1) const SizedBox(width: 12),
                  ],
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

class _RoundDot extends StatelessWidget {
  const _RoundDot({required this.label, required this.done, required this.color});
  final String label;
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(done ? Icons.check_circle : Icons.circle_outlined, size: 16, color: done ? color : theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall),
      ],
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
        Expanded(child: Text(game.title, style: DaypencilTheme.display(size: 20, color: theme.colorScheme.onSurface))),
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
