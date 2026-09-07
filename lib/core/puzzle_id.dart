import 'package:equatable/equatable.dart';

import 'edition_clock.dart';
import 'game_kind.dart';

/// A permanent identity for one puzzle: `word-2026-09-08-en-v1`, `quiz-2026-09-08-en-v1` or
/// `sudoku-2026-09-08-en-hard-v1`. A shared link always opens this exact
/// puzzle and this exact content version.
class PuzzleId extends Equatable {
  const PuzzleId({
    required this.game,
    required this.date,
    this.language = 'en',
    this.difficulty,
    this.version = 1,
  });

  final GameKind game;
  final DateTime date;
  final String language;
  final Difficulty? difficulty;
  final int version;

  static final RegExp _pattern = RegExp(
    r'^(word|sudoku|letters|crossword|quiz)'
    r'-(\d{4}-\d{2}-\d{2})'
    r'-([a-z]{2})'
    r'(?:-(easy|medium|hard))?'
    r'-v(\d+)$',
  );

  static PuzzleId parse(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) throw FormatException('Invalid puzzle id: $text');
    final game = GameKind.fromSlug(m.group(1)!);
    final difficulty = m.group(4) == null ? null : Difficulty.fromSlug(m.group(4)!);
    if (game == GameKind.sudoku && difficulty == null) {
      throw FormatException('Sudoku ids require a difficulty: $text');
    }
    if (game != GameKind.sudoku && difficulty != null) {
      throw FormatException('Only sudoku ids carry a difficulty: $text');
    }
    return PuzzleId(
      game: game,
      date: EditionClock.parseDate(m.group(2)!),
      language: m.group(3)!,
      difficulty: difficulty,
      version: int.parse(m.group(5)!),
    );
  }

  static PuzzleId? tryParse(String text) {
    try {
      return parse(text);
    } on FormatException {
      return null;
    }
  }

  String get dateString => EditionClock.formatDate(date);

  @override
  String toString() {
    final parts = [game.slug, dateString, language];
    if (difficulty != null) parts.add(difficulty!.slug);
    parts.add('v$version');
    return parts.join('-');
  }

  @override
  List<Object?> get props => [game, date, language, difficulty, version];
}
