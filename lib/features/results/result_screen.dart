import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/game_kind.dart';
import '../../core/game_result.dart';
import '../../core/theme.dart';
import '../../storage/local_store.dart';
import '../stats/stats_summary.dart';
import 'share_service.dart';

/// The common result screen: summary, comparison with a challenge, stats,
/// and the two share actions. Games push this after saving a result.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.result,
    required this.store,
    this.challenge,
    this.revealTitle,
    this.reveal,
    this.nextLabel,
    this.onNext,
  });

  final GameResult result;
  final LocalStore store;
  final GameResult? challenge;

  /// Optional explanation block, e.g. the real figure and its context.
  final String? revealTitle;
  final Widget? reveal;

  /// When set, a primary button that continues a flow (the news edition).
  final String? nextLabel;
  final VoidCallback? onNext;

  static Future<void> show(
    BuildContext context, {
    required GameResult result,
    required LocalStore store,
    GameResult? challenge,
    String? revealTitle,
    Widget? reveal,
    String? nextLabel,
    VoidCallback? onNext,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResultScreen(
          result: result,
          store: store,
          challenge: challenge,
          revealTitle: revealTitle,
          reveal: reveal,
          nextLabel: nextLabel,
          onNext: onNext,
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, String text, String toast) async {
    final ok = await ShareService.share(text, subject: 'Play the Paper');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? toast : 'Could not share')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.gameColors;
    final id = result.puzzleId;
    final stats = StatsSummary.forGame(store.resultsFor(id.game), id.game);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(ShareService.titleFor(id).toUpperCase(), style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              result.solved || result.game == GameKind.quiz ? _headline(result.game, result) : 'Not this time',
              style: PaperTheme.display(size: 30, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(result.summary(), style: theme.textTheme.titleLarge),
            Text(ShareService.dateLabel(id), style: theme.textTheme.bodySmall),
            if (result.shareLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(result.shareLines.join('\n'), style: theme.textTheme.bodyLarge?.copyWith(height: 1.3)),
            ],
            if (challenge != null) ...[
              const SizedBox(height: 16),
              _ChallengeCompare(mine: result, theirs: challenge!),
            ],
            if (reveal != null) ...[
              const SizedBox(height: 20),
              Container(height: 2, color: theme.colorScheme.onSurface),
              const SizedBox(height: 12),
              if (revealTitle != null)
                Text(revealTitle!, style: PaperTheme.display(size: 20, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              reveal!,
            ],
            const SizedBox(height: 20),
            Container(height: 1, color: colors.rule),
            const SizedBox(height: 12),
            Text('YOUR ${id.game.title.replaceFirst('The ', '').toUpperCase()} RECORD', style: theme.textTheme.labelSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                _Stat(label: 'Played', value: '${stats.played}'),
                _Stat(label: stats.rateLabel, value: stats.rateValue),
                _Stat(label: 'Streak', value: '${stats.currentStreak}'),
                _Stat(label: 'Best', value: '${stats.bestStreak}'),
              ],
            ),
            const SizedBox(height: 24),
            if (onNext != null) ...[
              FilledButton(onPressed: onNext, child: Text(nextLabel ?? 'Continue')),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Share result'),
              onPressed: () => _share(context, ShareService.resultText(result), 'Result shared'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('Challenge a friend'),
              onPressed: () => _share(context, ShareService.challengeText(result), 'Challenge shared'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Copy link'),
              onPressed: () async {
                final ok = await ShareService.copy(ShareService.puzzleUrl(id));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(ok ? 'Link copied' : 'Could not copy')));
              },
            ),
            if (onNext == null)
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to today'),
              ),
          ],
        ),
      ),
    );
  }

  String _headline(GameKind game, GameResult result) => switch (game) {
        GameKind.word => 'Word found',
        GameKind.sudoku => 'Grid complete',
        GameKind.letters => 'Well spelled',
        GameKind.crossword => 'All filled in',
        GameKind.quiz => switch (result.points ?? 0) {
            6 => 'Full marks',
            5 || 4 => 'Well read',
            3 || 2 => 'Not bad',
            _ => 'Tomorrow, then',
          },
      };
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value, style: PaperTheme.display(size: 24, color: theme.colorScheme.onSurface)),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ChallengeCompare extends StatelessWidget {
  const _ChallengeCompare({required this.mine, required this.theirs});
  final GameResult mine;
  final GameResult theirs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = _verdict();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CHALLENGE', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(verdict, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('You: ${mine.summary()}\nFriend: ${theirs.summary()}', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  String _verdict() {
    final c = _compare();
    if (c == null) return 'Same puzzle, compared';
    if (c > 0) return 'You beat your friend';
    if (c < 0) return 'Your friend did better';
    return 'A dead heat';
  }

  /// Positive when mine is better.
  int? _compare() {
    if (mine.solved != theirs.solved) return mine.solved ? 1 : -1;
    switch (mine.game) {
      case GameKind.word:
        if (mine.attempts == null || theirs.attempts == null) return null;
        return theirs.attempts!.compareTo(mine.attempts!);
      case GameKind.letters:
      case GameKind.quiz:
        if (mine.points == null || theirs.points == null) return null;
        return mine.points!.compareTo(theirs.points!);
      case GameKind.sudoku:
      case GameKind.crossword:
        final mh = mine.hints ?? 0, th = theirs.hints ?? 0;
        if (mh != th) return th.compareTo(mh);
        if (mine.seconds == null || theirs.seconds == null) return null;
        return theirs.seconds!.compareTo(mine.seconds!);
    }
  }
}
