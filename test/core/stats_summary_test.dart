import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/features/stats/stats_summary.dart';
import 'package:flutter_test/flutter_test.dart';

GameResult word(String date, {bool solved = true, int attempts = 3, bool archive = false}) => GameResult(
      puzzleId: PuzzleId.parse('word-$date-en-v1'),
      completedAt: DateTime.utc(2026),
      solved: solved,
      attempts: attempts,
      isArchivePlay: archive,
    );

void main() {
  test('streaks count consecutive days, archive plays excluded', () {
    final results = [
      word('2026-09-01'),
      word('2026-09-02'),
      word('2026-09-04', archive: true),
      word('2026-09-05'),
      word('2026-09-06'),
      word('2026-09-07'),
    ];
    final s = StatsSummary.forGame(results, GameKind.word, today: DateTime.utc(2026, 9, 7));
    expect(s.played, 6);
    expect(s.bestStreak, 3);
    expect(s.currentStreak, 3);
    expect(s.rateValue, '100%');
    expect(s.distribution[2], 6);
  });

  test('current streak survives until the day after the last play', () {
    final results = [word('2026-09-06'), word('2026-09-07')];
    expect(StatsSummary.forGame(results, GameKind.word, today: DateTime.utc(2026, 9, 8)).currentStreak, 2);
    expect(StatsSummary.forGame(results, GameKind.word, today: DateTime.utc(2026, 9, 9)).currentStreak, 0);
  });

  test('empty results are safe', () {
    final s = StatsSummary.forGame(const [], GameKind.letters);
    expect(s.played, 0);
    expect(s.rateValue, '–');
  });
}
