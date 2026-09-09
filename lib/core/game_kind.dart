/// How a game is grouped on the home page and scored by default.
enum GameCategory {
  classic('The classics'),
  logic('Logic'),
  play('Play'),
  editorial('From the stories'),
  quiz('The Quiz');

  const GameCategory(this.title);
  final String title;
}

enum GameKind {
  // The classics, seeded from the day's stories.
  word('word', 'Daily Word', GameCategory.classic),
  sudoku('sudoku', 'Sudoku', GameCategory.classic),
  letters('letters', 'Letters', GameCategory.classic),
  crossword('crossword', 'Mini Crossword', GameCategory.classic),
  // The news edition.
  quiz('quiz', 'The Quiz', GameCategory.quiz),
  // Logic puzzles, generated.
  bridges('bridges', 'Bridges', GameCategory.logic),
  binary('binary', 'Binary', GameCategory.logic),
  nonogram('nonogram', 'Nonogram', GameCategory.logic),
  kakuro('kakuro', 'Kakuro', GameCategory.logic),
  regions('regions', 'Regions', GameCategory.logic),
  loop('loop', 'Loop', GameCategory.logic),
  target('target', 'Target', GameCategory.logic),
  // Play: dexterity and score games with a daily challenge.
  tangram('tangram', 'Tangram', GameCategory.play),
  merge('merge', '2048', GameCategory.play),
  // Editorial games, written from the day's stories or an evergreen reserve.
  uncover('uncover', 'Uncover', GameCategory.editorial),
  fiveclues('fiveclues', 'Five Clues', GameCategory.editorial),
  groups('groups', 'Groups', GameCategory.editorial),
  linked('linked', 'Linked Clues', GameCategory.editorial),
  chronology('chronology', 'Before & After', GameCategory.editorial),
  crossmatch('crossmatch', 'Crossmatch', GameCategory.editorial),
  compass('compass', 'Word Compass', GameCategory.editorial);

  const GameKind(this.slug, this.title, this.category);

  final String slug;
  final String title;
  final GameCategory category;

  bool get isClassic => category == GameCategory.classic;
  bool get isNews => category == GameCategory.quiz;
  bool get isLogic => category == GameCategory.logic;
  bool get isEditorial => category == GameCategory.editorial;

  /// Games whose result is a time (and hints), like Sudoku.
  bool get isTimed =>
      this == sudoku || this == crossword || isLogic || this == tangram;

  static GameKind fromSlug(String slug) {
    for (final kind in values) {
      if (kind.slug == slug) return kind;
    }
    throw FormatException('Unknown game slug: $slug');
  }

  static GameKind? tryFromSlug(String slug) {
    for (final kind in values) {
      if (kind.slug == slug) return kind;
    }
    return null;
  }

  static List<GameKind> get classics =>
      values.where((k) => k.isClassic).toList(growable: false);

  static List<GameKind> inCategory(GameCategory c) =>
      values.where((k) => k.category == c).toList(growable: false);

  /// The core of every edition: the four classics and the quiz. Every other
  /// game is optional per edition and appears only when its manifest lists it.
  static List<GameKind> get core => const [word, sudoku, letters, crossword, quiz];

  /// The news edition is the quiz. The classics are seeded from the same
  /// stories but keep their own logic.
  static List<GameKind> get newsOrder => const [quiz];
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
