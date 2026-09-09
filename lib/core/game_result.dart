import 'package:equatable/equatable.dart';

import 'edition_clock.dart';
import 'game_kind.dart';
import 'puzzle_id.dart';

/// The outcome of one completed play of one puzzle.
///
/// Only summary numbers live here. Answers and move history never leave the
/// device. The compact [challengeCode] is what travels in a challenge link.
class GameResult extends Equatable {
  const GameResult({
    required this.puzzleId,
    required this.completedAt,
    required this.solved,
    this.attempts,
    this.points,
    this.maxPoints,
    this.seconds,
    this.hints,
    this.distanceKm,
    this.errorPct,
    this.shareLines = const [],
    this.isArchivePlay = false,
    this.note,
  });

  final PuzzleId puzzleId;
  final DateTime completedAt;
  final bool solved;

  /// Guesses used (Daily Word).
  final int? attempts;

  /// Points earned (Letters, The Quiz).
  final int? points;
  final int? maxPoints;

  /// Elapsed play time (Crossword, Sudoku).
  final int? seconds;

  /// Hints or reveals used (Crossword, Sudoku).
  final int? hints;

  /// Reserved for games that measure distance; unused today.
  final double? distanceKm;

  /// Reserved for games that measure estimation error; unused today.
  final double? errorPct;

  /// Optional spoiler-free emoji rows for the share card.
  final List<String> shareLines;

  /// True when this puzzle was played from the archive after its own date.
  final bool isArchivePlay;

  /// A game-specific one-line summary, e.g. `Score 5,432 · best tile 1024`.
  /// When set it is shown instead of the category default.
  final String? note;

  GameKind get game => puzzleId.game;

  /// One-line human summary, e.g. `Solved in 4/6` or `37 points`.
  String summary() {
    if (note != null && note!.isNotEmpty) return note!;
    switch (game) {
      case GameKind.word:
        return solved ? 'Solved in $attempts/6' : 'Not solved';
      case GameKind.quiz:
        return '$points/${maxPoints ?? 6}';
      case GameKind.letters:
        final max = maxPoints == null ? '' : ' of $maxPoints';
        return '$points points$max';
      case GameKind.merge:
        return points == null ? (solved ? 'Reached 2048' : 'Played') : 'Score $points';
      default:
        if (game.isTimed) {
          final time = seconds == null ? '' : ' in ${formatSeconds(seconds!)}';
          final h = (hints ?? 0) == 0 ? '' : ' · $hints hint${hints == 1 ? '' : 's'}';
          return solved ? 'Solved$time$h' : 'Not solved';
        }
        if (points != null) {
          final max = maxPoints == null ? '' : '/$maxPoints';
          return '$points$max';
        }
        if (attempts != null) return solved ? 'Solved in $attempts' : 'Not solved';
        return solved ? 'Solved' : 'Not solved';
    }
  }

  static String formatSeconds(int total) {
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Compact spoiler-free code carried in a challenge link, e.g. `s1.a4`.
  String challengeCode() {
    final parts = <String>['s${solved ? 1 : 0}'];
    if (attempts != null) parts.add('a$attempts');
    if (points != null) parts.add('p$points');
    if (maxPoints != null) parts.add('m$maxPoints');
    if (seconds != null) parts.add('t$seconds');
    if (hints != null) parts.add('h$hints');
    if (distanceKm != null) parts.add('d${distanceKm!.round()}');
    if (errorPct != null) parts.add('e${errorPct!.round()}');
    return parts.join('.');
  }

  /// Parses a [challengeCode]. Unknown tokens are ignored; a malformed code
  /// returns null so a bad link never breaks play.
  static GameResult? fromChallengeCode(PuzzleId id, String code) {
    if (code.isEmpty) return null;
    bool solved = false;
    int? attempts, points, maxPoints, seconds, hints;
    double? distanceKm, errorPct;
    for (final token in code.split('.')) {
      if (token.length < 2) return null;
      final value = int.tryParse(token.substring(1));
      if (value == null || value < 0) return null;
      switch (token[0]) {
        case 's':
          solved = value == 1;
        case 'a':
          attempts = value;
        case 'p':
          points = value;
        case 'm':
          maxPoints = value;
        case 't':
          seconds = value;
        case 'h':
          hints = value;
        case 'd':
          distanceKm = value.toDouble();
        case 'e':
          errorPct = value.toDouble();
        default:
          continue;
      }
    }
    return GameResult(
      puzzleId: id,
      completedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      solved: solved,
      attempts: attempts,
      points: points,
      maxPoints: maxPoints,
      seconds: seconds,
      hints: hints,
      distanceKm: distanceKm,
      errorPct: errorPct,
    );
  }

  Map<String, dynamic> toJson() => {
        'puzzleId': puzzleId.toString(),
        'completedAt': completedAt.toUtc().toIso8601String(),
        'solved': solved,
        if (attempts != null) 'attempts': attempts,
        if (points != null) 'points': points,
        if (maxPoints != null) 'maxPoints': maxPoints,
        if (seconds != null) 'seconds': seconds,
        if (hints != null) 'hints': hints,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (errorPct != null) 'errorPct': errorPct,
        if (shareLines.isNotEmpty) 'shareLines': shareLines,
        'isArchivePlay': isArchivePlay,
        if (note != null) 'note': note,
      };

  static GameResult fromJson(Map<String, dynamic> json) => GameResult(
        puzzleId: PuzzleId.parse(json['puzzleId'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String).toUtc(),
        solved: json['solved'] as bool,
        attempts: json['attempts'] as int?,
        points: json['points'] as int?,
        maxPoints: json['maxPoints'] as int?,
        seconds: json['seconds'] as int?,
        hints: json['hints'] as int?,
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        errorPct: (json['errorPct'] as num?)?.toDouble(),
        shareLines: (json['shareLines'] as List?)?.cast<String>() ?? const [],
        isArchivePlay: json['isArchivePlay'] as bool? ?? false,
        note: json['note'] as String?,
      );

  String get editionDateLabel => EditionClock.formatDate(puzzleId.date);

  @override
  List<Object?> get props => [
        puzzleId,
        completedAt,
        solved,
        attempts,
        points,
        maxPoints,
        seconds,
        hints,
        distanceKm,
        errorPct,
        shareLines,
        isArchivePlay,
        note,
      ];
}
