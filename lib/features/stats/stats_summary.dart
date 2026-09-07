import '../../core/game_kind.dart';
import '../../core/game_result.dart';

/// Per-game statistics derived from stored results. Streaks count
/// consecutive edition dates played on their own day; archive plays count
/// toward totals but never toward streaks.
class StatsSummary {
  const StatsSummary({
    required this.game,
    required this.played,
    required this.solved,
    required this.currentStreak,
    required this.bestStreak,
    required this.rateLabel,
    required this.rateValue,
    required this.distribution,
  });

  final GameKind game;
  final int played;
  final int solved;
  final int currentStreak;
  final int bestStreak;
  final String rateLabel;
  final String rateValue;

  /// Attempt distribution for guess games (index 0 = 1 attempt).
  final List<int> distribution;

  static StatsSummary forGame(List<GameResult> results, GameKind game, {DateTime? today}) {
    final list = results.where((r) => r.game == game).toList()..sort((a, b) => a.puzzleId.date.compareTo(b.puzzleId.date));
    final played = list.length;
    final solved = list.where((r) => r.solved).length;

    final dates = list.where((r) => !r.isArchivePlay).map((r) => r.puzzleId.date).toSet().toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in dates) {
      if (prev != null && d.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    var current = 0;
    if (dates.isNotEmpty) {
      final last = dates.last;
      final ref = today ?? last;
      final gap = ref.difference(last).inDays;
      if (gap <= 1) {
        current = 1;
        for (var i = dates.length - 1; i > 0; i--) {
          if (dates[i].difference(dates[i - 1]).inDays == 1) {
            current++;
          } else {
            break;
          }
        }
      }
    }

    final dist = List<int>.filled(6, 0);
    for (final r in list) {
      if (r.solved && r.attempts != null && r.attempts! >= 1 && r.attempts! <= 6) dist[r.attempts! - 1]++;
    }

    String rateLabel;
    String rateValue;
    switch (game) {
      case GameKind.letters:
        final pts = list.map((r) => r.points ?? 0).toList();
        rateLabel = 'Avg points';
        rateValue = pts.isEmpty ? '–' : (pts.reduce((a, b) => a + b) / pts.length).round().toString();
      case GameKind.number:
        final e = list.where((r) => r.errorPct != null).map((r) => r.errorPct!).toList();
        rateLabel = 'Avg off';
        rateValue = e.isEmpty ? '–' : '${(e.reduce((a, b) => a + b) / e.length).round()}%';
      case GameKind.where:
        final d = list.where((r) => r.distanceKm != null).map((r) => r.distanceKm!).toList();
        rateLabel = 'Avg km';
        rateValue = d.isEmpty ? '–' : (d.reduce((a, b) => a + b) / d.length).round().toString();
      case GameKind.sudoku:
      case GameKind.crossword:
        final t = list.where((r) => r.solved && r.seconds != null).map((r) => r.seconds!).toList();
        rateLabel = 'Best time';
        rateValue = t.isEmpty ? '–' : GameResult.formatSeconds(t.reduce((a, b) => a < b ? a : b));
      case GameKind.word:
      case GameKind.correct:
        rateLabel = 'Win rate';
        rateValue = played == 0 ? '–' : '${(solved * 100 / played).round()}%';
    }

    return StatsSummary(
      game: game,
      played: played,
      solved: solved,
      currentStreak: current,
      bestStreak: best,
      rateLabel: rateLabel,
      rateValue: rateValue,
      distribution: dist,
    );
  }
}
