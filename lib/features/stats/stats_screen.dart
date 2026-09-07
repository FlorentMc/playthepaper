import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../content/content_repository.dart';
import '../../core/game_kind.dart';
import '../../core/theme.dart';
import '../../shared/widgets/game_shell.dart';
import '../../storage/local_store.dart';
import 'stats_summary.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final today = context.read<EditionController>().todayDate;
    final theme = Theme.of(context);
    final results = store.allResults();
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _History(results: results, today: today),
            const SizedBox(height: 20),
            for (final game in GameKind.values) ...[
              _GameStats(summary: StatsSummary.forGame(results, game, today: today)),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            Text('Streaks count editions played on their own day. Archive plays count toward totals only.',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.results, required this.today});
  final List<dynamic> results;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final played = <DateTime, int>{};
    for (final r in results) {
      final d = r.puzzleId.date as DateTime;
      played[d] = (played[d] ?? 0) + 1;
    }
    const days = 28;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LAST FOUR WEEKS', style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        const Rule(),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = days - 1; i >= 0; i--)
              Builder(builder: (context) {
                final d = DateTime.utc(today.year, today.month, today.day - i);
                final n = played[d] ?? 0;
                return Tooltip(
                  message: '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}: $n played',
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: n == 0 ? colors.cellHighlight : colors.correct.withValues(alpha: 0.35 + 0.65 * (n.clamp(1, 7) / 7)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.rule),
                    ),
                    child: n == 0
                        ? null
                        : Center(child: Text('$n', style: theme.textTheme.labelSmall?.copyWith(color: colors.onFeedback))),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}

class _GameStats extends StatelessWidget {
  const _GameStats({required this.summary});
  final StatsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.game.title, style: DaypencilTheme.display(size: 18, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 10),
            Row(
              children: [
                _Cell('Played', '${summary.played}'),
                _Cell(summary.rateLabel, summary.rateValue),
                _Cell('Streak', '${summary.currentStreak}'),
                _Cell('Best', '${summary.bestStreak}'),
              ],
            ),
            if (summary.game == GameKind.word || summary.game == GameKind.correct) ...[
              const SizedBox(height: 12),
              _Distribution(summary.distribution),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value, style: DaypencilTheme.display(size: 22, color: theme.colorScheme.onSurface)),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution(this.counts);
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final max = counts.fold<int>(0, (m, c) => c > m ? c : m);
    return Column(
      children: [
        for (var i = 0; i < counts.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(width: 16, child: Text('${i + 1}', style: theme.textTheme.labelMedium)),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: max == 0 ? 0.06 : (0.06 + 0.94 * counts[i] / max),
                      child: Container(
                        height: 18,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        color: counts[i] == 0 ? colors.absent : colors.correct,
                        child: Text('${counts[i]}', style: theme.textTheme.labelSmall?.copyWith(color: colors.onFeedback)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
