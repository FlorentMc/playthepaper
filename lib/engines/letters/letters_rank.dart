/// Ranks by share of the puzzle's maximum score. A rank is reached when
/// points ≥ ceil(percent × maxScore / 100); Beginner is always reached.
enum LettersRank {
  beginner('Beginner', 0),
  goodStart('Good start', 2),
  movingUp('Moving up', 5),
  good('Good', 8),
  solid('Solid', 15),
  nice('Nice', 25),
  great('Great', 40),
  amazing('Amazing', 50),
  genius('Genius', 70);

  const LettersRank(this.label, this.percent);

  final String label;
  final int percent;

  double get fraction => percent / 100;

  /// The minimum points needed for this rank on a puzzle worth [maxScore].
  int threshold(int maxScore) => (percent * maxScore + 99) ~/ 100;

  static LettersRank rankFor(int points, int maxScore) {
    for (final rank in values.reversed) {
      if (points >= rank.threshold(maxScore)) return rank;
    }
    return beginner;
  }

  /// The rank after this one, or null at Genius.
  LettersRank? get next => this == genius ? null : values[index + 1];
}
