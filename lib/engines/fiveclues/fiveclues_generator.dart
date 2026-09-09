import 'dart:convert';
import 'dart:io';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'fiveclues_puzzle.dart';
import 'fiveclues_text.dart';

/// One written Five Clues puzzle, from the evergreen reserve or from a news
/// template: `{"topic", "payload", "reveal", "sources", "editorNotes"}`.
class FiveCluesItem {
  const FiveCluesItem({
    required this.topic,
    required this.puzzle,
    required this.payload,
    required this.reveal,
    required this.sources,
    this.editorNotes,
  });

  final String topic;
  final FiveCluesPuzzle puzzle;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> reveal;
  final List<SourceRef> sources;

  /// The alternative readings the editor checked and why they do not fit.
  final String? editorNotes;

  /// Parses and checks an item. Beyond the engine rules, an item must cite
  /// at least one source and the answer must appear in one of the cited
  /// excerpts, so nothing ships unsourced.
  static FiveCluesItem parse(Map<String, dynamic> item) {
    final payload = item['payload'];
    final reveal = item['reveal'];
    if (payload is! Map || reveal is! Map) {
      throw const FormatException('Five Clues item needs "payload" and "reveal"');
    }
    final puzzle = FiveCluesPuzzle.parse(Map<String, dynamic>.from(payload), Map<String, dynamic>.from(reveal));
    final rawTopic = item['topic'];
    if (rawTopic is! String || rawTopic.trim().isEmpty) {
      throw const FormatException('Five Clues item needs a "topic"');
    }
    final rawSources = item['sources'];
    if (rawSources is! List || rawSources.isEmpty) {
      throw const FormatException('Five Clues item needs "sources"');
    }
    final sources = [for (final s in rawSources) SourceRef.fromJson(Map<String, dynamic>.from(s as Map))];
    final named = sources.any(
      (s) => [puzzle.answer, ...puzzle.aliases].any((a) => FiveCluesText.containsPhrase(s.excerpt, a)),
    );
    if (!named) {
      throw FormatException('Five Clues answer "${puzzle.answer}" appears in no source excerpt');
    }
    final notes = item['editorNotes'];
    return FiveCluesItem(
      topic: rawTopic.trim(),
      puzzle: puzzle,
      payload: Map<String, dynamic>.from(payload),
      reveal: Map<String, dynamic>.from(reveal),
      sources: sources,
      editorNotes: notes is String && notes.trim().isNotEmpty ? notes : null,
    );
  }
}

/// Picks a reserve puzzle for each date and wraps it in the record envelope.
///
/// The pick for a date is `fnv1a('fiveclues-<date>') % count`, stepped
/// forward past any file used on the previous [reuseSpan] dates, which are
/// computed the same way from [epoch]. Adding a file to the reserve changes
/// later picks, which is fine: puzzle files are immutable once published and
/// the builder only writes dates it has not written before.
class FiveCluesGenerator {
  FiveCluesGenerator({this.reserveDir = defaultReserveDir}) {
    _load();
  }

  static const String slug = 'fiveclues';
  static const String defaultReserveDir = 'content_src/editorial/fiveclues';
  static const int minReserve = 30;
  static const int reuseWindow = 30;
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  final String reserveDir;
  final List<String> _files = [];
  final List<FiveCluesItem> _items = [];
  final List<String> problems = [];
  final Map<DateTime, int> _picks = {};

  /// 32-bit FNV-1a over the code units of [text]; stable on every platform.
  static int fnv1a(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static int seedFor(DateTime date) => fnv1a('$slug-${EditionClock.formatDate(date)}');

  /// Reserve file names, in the order used for picking.
  List<String> get files => List.unmodifiable(_files);

  List<FiveCluesItem> get items => List.unmodifiable(_items);

  void _load() {
    final dir = Directory(reserveDir);
    if (!dir.existsSync()) {
      problems.add('$reserveDir does not exist');
      return;
    }
    final paths = dir.listSync().whereType<File>().map((f) => f.path).where((p) => p.endsWith('.json')).toList()..sort();
    for (final path in paths) {
      final name = path.split(Platform.pathSeparator).last;
      try {
        final json = jsonDecode(File(path).readAsStringSync());
        if (json is! Map<String, dynamic>) throw const FormatException('not a JSON object');
        _items.add(FiveCluesItem.parse(json));
        _files.add(name);
      } on FormatException catch (e) {
        problems.add('$name: ${e.message}');
      }
    }
  }

  void _ensureReady() {
    if (problems.isNotEmpty) throw StateError('Five Clues reserve has problems: ${problems.join('; ')}');
    if (_items.length < minReserve) {
      throw StateError('Five Clues reserve has ${_items.length} puzzles; at least $minReserve are needed');
    }
  }

  /// How many previous dates a pick avoids. A reserve of exactly
  /// [minReserve] files cannot dodge thirty earlier picks and still have a
  /// choice, so the span is one less than the reserve when the reserve is
  /// small: every file is then used once per cycle.
  int get reuseSpan {
    _ensureReady();
    return _items.length <= reuseWindow ? _items.length - 1 : reuseWindow;
  }

  /// The reserve index used on [date].
  int pickFor(DateTime date) {
    _ensureReady();
    final day = DateTime.utc(date.year, date.month, date.day);
    final cached = _picks[day];
    if (cached != null) return cached;
    var cursor = day.isBefore(epoch) ? day : epoch;
    while (!cursor.isAfter(day)) {
      _picks.putIfAbsent(cursor, () => _pick(cursor));
      cursor = DateTime.utc(cursor.year, cursor.month, cursor.day + 1);
    }
    return _picks[day]!;
  }

  int _pick(DateTime day) {
    final count = _items.length;
    final span = count <= reuseWindow ? count - 1 : reuseWindow;
    final used = <int>{};
    for (var k = 1; k <= span; k++) {
      final earlier = DateTime.utc(day.year, day.month, day.day - k);
      if (earlier.isBefore(epoch)) break;
      final pick = _picks[earlier];
      if (pick != null) used.add(pick);
    }
    var index = seedFor(day) % count;
    if (used.length >= count) return index;
    while (used.contains(index)) {
      index = (index + 1) % count;
    }
    return index;
  }

  PuzzleRecord generate(DateTime date) => _wrap(date, _items[pickFor(date)]);

  /// The record for a news item carried by an edition template, validated
  /// exactly like a reserve file.
  PuzzleRecord fromTemplate(DateTime date, Map<String, dynamic> item, {String? storyId}) =>
      _wrap(date, FiveCluesItem.parse(item), storyId: storyId);

  PuzzleRecord _wrap(DateTime date, FiveCluesItem item, {String? storyId}) => PuzzleRecord(
        id: PuzzleId(game: GameKind.fiveclues, date: DateTime.utc(date.year, date.month, date.day)),
        locale: 'en-GB',
        contentVersion: 1,
        scoringVersion: 1,
        payload: item.payload,
        reveal: item.reveal,
        storyId: storyId,
        sources: item.sources,
      );
}
