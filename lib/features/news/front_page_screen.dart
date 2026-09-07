import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart';
import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../../core/game_result.dart';
import '../../core/theme.dart';
import '../../shared/widgets/game_shell.dart';
import '../../storage/local_store.dart';
import '../results/share_service.dart';

/// The payoff for the whole paper: the day's stories, each tagged with the
/// questions and puzzles it fed and how the player did on them.
class FrontPageScreen extends StatefulWidget {
  const FrontPageScreen({super.key, required this.dateText});
  final String dateText;

  @override
  State<FrontPageScreen> createState() => _FrontPageScreenState();
}

class _FrontPageScreenState extends State<FrontPageScreen> {
  late Future<EditionManifest> _future;
  bool _revealAll = false;

  @override
  void initState() {
    super.initState();
    final date = parseRouteDate(widget.dateText);
    final repo = context.read<ContentRepository>();
    _future = date == null ? Future.error(const ContentNotFound('date')) : repo.edition(date);
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
            final quizId = m.puzzleFor(GameKind.quiz);
            final quizResult = quizId == null ? null : store.result(quizId);
            final unlocked = quizResult != null || _revealAll;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Text('The Front Page',
                    style: DaypencilTheme.display(size: 30, color: theme.colorScheme.onSurface), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(DateFormat('EEEE d MMMM yyyy').format(m.date.toUtc()).toUpperCase(),
                    style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
                Text(m.kind == EditionKind.evergreen ? m.label : 'Today\'s stories',
                    style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Rule(thick: true),
                const SizedBox(height: 12),
                if (!unlocked) ...[
                  Text(
                    'The stories unlock when you finish the quiz. You can reveal them now if you would rather read first.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (quizId != null)
                        FilledButton(
                          onPressed: () => context.push('/news/${m.dateString}'),
                          child: const Text('Play the quiz'),
                        ),
                      const SizedBox(width: 10),
                      TextButton(onPressed: () => setState(() => _revealAll = true), child: const Text('Reveal')),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                for (var i = 0; i < m.stories.length; i++) ...[
                  _StoryCard(
                    index: i + 1,
                    story: m.stories[i],
                    seeds: m.seeds[m.stories[i].id] ?? const [],
                    manifest: m,
                    unlocked: unlocked,
                  ),
                  const SizedBox(height: 14),
                ],
                if (unlocked) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share the edition'),
                    onPressed: () async {
                      final ok = await ShareService.share(_editionText(m, store), subject: 'Daypencil');
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(ok ? 'Edition shared' : 'Could not share')));
                    },
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.go('/'), child: const Text('Back to today')),
              ],
            );
          },
        ),
      ),
    );
  }

  String _editionText(EditionManifest m, LocalStore store) {
    final lines = <String>['Daypencil · ${ShareService.dateLabel(m.puzzles.first)}'];
    for (final g in [GameKind.quiz, GameKind.word, GameKind.letters, GameKind.crossword]) {
      final id = m.puzzleFor(g);
      final r = id == null ? null : store.result(id);
      lines.add('${g.title}: ${r?.summary() ?? 'not played'}');
    }
    lines.add('$kSiteBaseUrl/e/${m.dateString}');
    return lines.join('\n');
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.index,
    required this.story,
    required this.seeds,
    required this.manifest,
    required this.unlocked,
  });

  final int index;
  final Story story;
  final List<String> seeds;
  final EditionManifest manifest;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final store = context.watch<LocalStore>();

    if (!unlocked) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: colors.subtle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Story $index', style: theme.textTheme.titleMedium),
                    if (seeds.isNotEmpty) Text(_seedSummary(), style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STORY $index', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(story.headline, style: DaypencilTheme.display(size: 21, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text(story.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('${story.publisher} · Read the story'),
              onPressed: () => launchUrl(Uri.parse(story.url), mode: LaunchMode.externalApplication),
            ),
            if (seeds.isNotEmpty) ...[
              const Rule(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [for (final s in seeds) _SeedChip(seed: s, manifest: manifest, store: store)],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _seedSummary() {
    final q = seeds.where((s) => s.startsWith('quiz:')).length;
    final others = seeds.where((s) => !s.startsWith('quiz:')).map((s) => s.split(':').first).toSet();
    final parts = <String>[
      if (q > 0) '$q question${q == 1 ? '' : 's'}',
      for (final o in others) GameKind.fromSlug(o).title,
    ];
    return parts.join(' · ');
  }
}

/// `quiz:3` → "Q3 ✓", `word` → "Daily Word · Solved in 2/6", `crossword:5 Across` → "5 Across".
class _SeedChip extends StatelessWidget {
  const _SeedChip({required this.seed, required this.manifest, required this.store});
  final String seed;
  final EditionManifest manifest;
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final parts = seed.split(':');
    final game = GameKind.fromSlug(parts.first);
    final detail = parts.length > 1 ? parts.sublist(1).join(':') : null;
    final id = manifest.puzzleFor(game);
    final GameResult? result = id == null ? null : store.result(id);

    String label;
    if (game == GameKind.quiz) {
      label = 'Question $detail';
      if (result != null && detail != null) {
        final n = int.tryParse(detail);
        final strip = result.shareLines.isEmpty ? '' : result.shareLines.first;
        final marks = strip.runes.where((r) => r != 0x2B50).toList();
        if (n != null && n >= 1 && n <= marks.length) {
          label = 'Question $detail ${marks[n - 1] == 0x1F7E9 ? '✓' : '✗'}';
        }
      }
    } else {
      label = detail == null ? game.title : '${game.title} $detail';
      if (result != null) label = '$label · ${result.summary()}';
    }
    return Chip(
      avatar: Icon(
        result != null ? Icons.check_circle : Icons.circle_outlined,
        size: 16,
        color: result != null ? colors.correct : colors.subtle,
      ),
      label: Text(label, style: theme.textTheme.labelMedium),
      onDeleted: null,
    );
  }
}
