import 'package:equatable/equatable.dart';

import '../core/edition_clock.dart';
import '../core/game_kind.dart';
import '../core/puzzle_id.dart';

/// The content format shared by the app, the bundled starter content, the
/// publisher and the validator. Every file is plain JSON.
///
/// Layout (identical on disk, in the bundle and on the web host):
///
///   content/index.json                 -> ContentIndex
///   content/editions/2026-09-08.json   -> EditionManifest
///   content/puzzles/[puzzle id].json   -> PuzzleRecord
///
/// A puzzle file is immutable once published. A correction is a new version
/// with a new id; the edition manifest is the only file that changes.

Never _missing(String field, String where) =>
    throw FormatException('Missing "$field" in $where');

Map<String, dynamic> _map(Object? v, String field, String where) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return _missing(field, where);
}

String _string(Map<String, dynamic> json, String field, String where) {
  final v = json[field];
  if (v is String && v.isNotEmpty) return v;
  return _missing(field, where);
}

int _int(Map<String, dynamic> json, String field, String where) {
  final v = json[field];
  if (v is int) return v;
  return _missing(field, where);
}

class ContentIndex extends Equatable {
  const ContentIndex({required this.dates, required this.latest});

  /// Every edition date available, ascending.
  final List<DateTime> dates;
  final DateTime latest;

  static ContentIndex fromJson(Map<String, dynamic> json) {
    final raw = json['dates'];
    if (raw is! List || raw.isEmpty) _missing('dates', 'index');
    final dates = raw
        .map((d) => EditionClock.parseDate(d as String))
        .toList()
      ..sort();
    return ContentIndex(
      dates: dates,
      latest: EditionClock.parseDate(_string(json, 'latest', 'index')),
    );
  }

  Map<String, dynamic> toJson() => {
        'dates': dates.map(EditionClock.formatDate).toList(),
        'latest': EditionClock.formatDate(latest),
      };

  @override
  List<Object?> get props => [dates, latest];
}

enum EditionKind {
  news('news'),
  evergreen('evergreen');

  const EditionKind(this.slug);
  final String slug;

  static EditionKind fromSlug(String s) =>
      values.firstWhere((k) => k.slug == s, orElse: () => throw FormatException('Unknown edition kind: $s'));
}

/// A story behind the day's edition. Stories feed the quiz questions and
/// seed the classics; the manifest's [EditionManifest.seeds] says which.
class Story extends Equatable {
  const Story({
    required this.id,
    required this.headline,
    required this.summary,
    required this.publisher,
    required this.url,
    required this.publishedAt,
  });

  final String id;
  final String headline;

  /// Two or three plain sentences explaining the story.
  final String summary;
  final String publisher;
  final String url;
  final String publishedAt;

  static Story fromJson(Map<String, dynamic> json) {
    const where = 'story';
    return Story(
      id: _string(json, 'id', where),
      headline: _string(json, 'headline', where),
      summary: _string(json, 'summary', where),
      publisher: _string(json, 'publisher', where),
      url: _string(json, 'url', where),
      publishedAt: _string(json, 'publishedAt', where),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'headline': headline,
        'summary': summary,
        'publisher': publisher,
        'url': url,
        'publishedAt': publishedAt,
      };

  @override
  List<Object?> get props => [id, headline, summary, publisher, url, publishedAt];
}

/// Lists the exact puzzle versions for one date.
class EditionManifest extends Equatable {
  const EditionManifest({
    required this.date,
    required this.kind,
    required this.label,
    required this.puzzles,
    required this.stories,
    required this.version,
    this.seeds = const {},
    this.publishedAt,
    this.correctionNote,
  });

  final DateTime date;
  final EditionKind kind;

  /// Shown on the home page, e.g. `Evergreen · Science` or `Today`.
  final String label;

  /// Every puzzle in the edition. Sudoku appears three times, once per difficulty.
  final List<PuzzleId> puzzles;
  final List<Story> stories;
  final int version;

  /// Story id → what it fed, e.g. `["quiz:1", "quiz:4", "word", "crossword:5 Across"]`.
  final Map<String, List<String>> seeds;
  final String? publishedAt;

  /// Present when a puzzle in this edition was revised after opening.
  final String? correctionNote;

  String get dateString => EditionClock.formatDate(date);

  PuzzleId? puzzleFor(GameKind game, {Difficulty? difficulty}) {
    for (final p in puzzles) {
      if (p.game == game && p.difficulty == difficulty) return p;
    }
    return null;
  }

  Story? story(String id) => stories.where((s) => s.id == id).firstOrNull;

  bool get isComplete {
    for (final g in GameKind.values) {
      if (g == GameKind.sudoku) {
        for (final d in Difficulty.values) {
          if (puzzleFor(g, difficulty: d) == null) return false;
        }
      } else if (puzzleFor(g) == null) {
        return false;
      }
    }
    return stories.length >= 3;
  }

  static EditionManifest fromJson(Map<String, dynamic> json) {
    const where = 'edition';
    final date = EditionClock.parseDate(_string(json, 'date', where));
    final rawPuzzles = json['puzzles'];
    if (rawPuzzles is! List) _missing('puzzles', where);
    final puzzles = rawPuzzles.map((p) => PuzzleId.parse(p as String)).toList();
    for (final p in puzzles) {
      if (p.date != date) {
        throw FormatException('Puzzle ${p.toString()} does not belong to edition ${EditionClock.formatDate(date)}');
      }
    }
    final rawStories = json['stories'];
    if (rawStories is! List) _missing('stories', where);
    final rawSeeds = json['seeds'];
    final seeds = <String, List<String>>{};
    if (rawSeeds is Map) {
      for (final e in rawSeeds.entries) {
        final v = e.value;
        if (v is! List) throw FormatException('seeds for ${e.key} must be a list');
        seeds[e.key as String] = v.map((x) => x.toString()).toList();
      }
    }
    return EditionManifest(
      date: date,
      kind: EditionKind.fromSlug(_string(json, 'kind', where)),
      label: _string(json, 'label', where),
      puzzles: puzzles,
      stories: rawStories.map((s) => Story.fromJson(_map(s, 'story', where))).toList(),
      version: _int(json, 'version', where),
      seeds: seeds,
      publishedAt: json['publishedAt'] as String?,
      correctionNote: json['correctionNote'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': dateString,
        'kind': kind.slug,
        'label': label,
        'puzzles': puzzles.map((p) => p.toString()).toList(),
        'stories': stories.map((s) => s.toJson()).toList(),
        'version': version,
        if (seeds.isNotEmpty) 'seeds': seeds,
        if (publishedAt != null) 'publishedAt': publishedAt,
        if (correctionNote != null) 'correctionNote': correctionNote,
      };

  @override
  List<Object?> get props => [date, kind, label, puzzles, stories, version, seeds, publishedAt, correctionNote];
}

/// A source passage backing a news puzzle.
class SourceRef extends Equatable {
  const SourceRef({required this.publisher, required this.url, required this.excerpt});

  final String publisher;
  final String url;
  final String excerpt;

  static SourceRef fromJson(Map<String, dynamic> json) => SourceRef(
        publisher: _string(json, 'publisher', 'source'),
        url: _string(json, 'url', 'source'),
        excerpt: _string(json, 'excerpt', 'source'),
      );

  Map<String, dynamic> toJson() => {'publisher': publisher, 'url': url, 'excerpt': excerpt};

  @override
  List<Object?> get props => [publisher, url, excerpt];
}

/// The common puzzle record. [payload] is what the client needs to play and
/// [reveal] is what it needs to check answers and explain the result. Each
/// game's engine documents and validates its own payload and reveal shapes.
class PuzzleRecord extends Equatable {
  const PuzzleRecord({
    required this.id,
    required this.locale,
    required this.contentVersion,
    required this.scoringVersion,
    required this.payload,
    required this.reveal,
    this.dictionaryVersion,
    this.storyId,
    this.sources = const [],
  });

  final PuzzleId id;
  final String locale;
  final int contentVersion;
  final int scoringVersion;
  final String? dictionaryVersion;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> reveal;

  /// The story that seeded this puzzle, when there is one. Quiz questions
  /// reference their stories individually inside the payload.
  final String? storyId;
  final List<SourceRef> sources;

  GameKind get game => id.game;
  DateTime get date => id.date;
  Difficulty? get difficulty => id.difficulty;

  static PuzzleRecord fromJson(Map<String, dynamic> json) {
    const where = 'puzzle';
    final id = PuzzleId.parse(_string(json, 'id', where));
    final game = _string(json, 'game', where);
    if (game != id.game.slug) throw FormatException('Puzzle $id declares game "$game"');
    final rawSources = json['sources'];
    final record = PuzzleRecord(
      id: id,
      locale: _string(json, 'locale', where),
      contentVersion: _int(json, 'contentVersion', where),
      scoringVersion: _int(json, 'scoringVersion', where),
      dictionaryVersion: json['dictionaryVersion'] as String?,
      payload: _map(json['payload'], 'payload', where),
      reveal: _map(json['reveal'], 'reveal', where),
      storyId: json['storyId'] as String?,
      sources: rawSources is List
          ? rawSources.map((s) => SourceRef.fromJson(_map(s, 'source', where))).toList()
          : const [],
    );
    if (record.contentVersion != id.version) {
      throw FormatException('Puzzle $id contentVersion ${record.contentVersion} does not match id');
    }
    return record;
  }

  Map<String, dynamic> toJson() => {
        'id': id.toString(),
        'game': id.game.slug,
        'editionDate': id.dateString,
        'locale': locale,
        if (id.difficulty != null) 'difficulty': id.difficulty!.slug,
        'contentVersion': contentVersion,
        'scoringVersion': scoringVersion,
        if (dictionaryVersion != null) 'dictionaryVersion': dictionaryVersion,
        'payload': payload,
        'reveal': reveal,
        if (storyId != null) 'storyId': storyId,
        if (sources.isNotEmpty) 'sources': sources.map((s) => s.toJson()).toList(),
      };

  @override
  List<Object?> get props => [id, locale, contentVersion, scoringVersion, dictionaryVersion, payload, reveal, storyId, sources];
}
