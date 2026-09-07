enum GameKind {
  word('word', 'Daily Word', isClassic: true),
  sudoku('sudoku', 'Sudoku', isClassic: true),
  letters('letters', 'Letters', isClassic: true),
  crossword('crossword', 'Mini Crossword', isClassic: true),
  correct('correct', 'Correct', isClassic: false),
  number('number', 'The Number', isClassic: false),
  where('where', 'Where', isClassic: false);

  const GameKind(this.slug, this.title, {required this.isClassic});

  final String slug;
  final String title;
  final bool isClassic;

  bool get isNews => !isClassic;

  static GameKind fromSlug(String slug) {
    for (final kind in values) {
      if (kind.slug == slug) return kind;
    }
    throw FormatException('Unknown game slug: $slug');
  }

  static List<GameKind> get classics =>
      values.where((k) => k.isClassic).toList(growable: false);

  /// The fixed order of the news edition.
  static List<GameKind> get newsOrder => const [correct, number, where];
}

enum Difficulty {
  easy('easy', 'Easy'),
  medium('medium', 'Medium'),
  hard('hard', 'Hard');

  const Difficulty(this.slug, this.label);
  final String slug;
  final String label;

  static Difficulty fromSlug(String slug) {
    for (final d in values) {
      if (d.slug == slug) return d;
    }
    throw FormatException('Unknown difficulty: $slug');
  }
}
