import 'dart:convert';
import 'dart:io';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'crossmatch_puzzle.dart';

/// One written puzzle from the evergreen reserve or a news template:
/// `{"topic", "payload", "reveal", "sources", "editorNotes"}`.
class CrossmatchItem {
  const CrossmatchItem({
    required this.topic,
    required this.puzzle,
    required this.payload,
    required this.reveal,
    required this.sources,
    this.editorNotes,
  });

  final String topic;
  final CrossmatchPuzzle puzzle;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> reveal;
  final List<SourceRef> sources;

  /// The alternatives the editor checked and why they do not fit.
  final String? editorNotes;

  /// Parses and checks an item. Beyond the engine rules, every tile must be
  /// named in at least one cited excerpt, so no answer ships unsourced.
  static CrossmatchItem parse(Map<String, dynamic> item) {
    final payload = item['payload'];
    final reveal = item['reveal'];
    if (payload is! Map || reveal is! Map) throw const FormatException('Crossmatch item needs "payload" and "reveal"');
    final puzzle = CrossmatchPuzzle.parse(Map<String, dynamic>.from(payload), Map<String, dynamic>.from(reveal));
    final rawTopic = item['topic'];
    final topic = rawTopic is String && rawTopic.trim().isNotEmpty ? rawTopic.trim() : puzzle.title;
    if (topic == null) throw const FormatException('Crossmatch item needs a "topic"');
    final rawSources = item['sources'];
    if (rawSources is! List || rawSources.isEmpty) throw const FormatException('Crossmatch item needs "sources"');
    final sources = [for (final s in rawSources) SourceRef.fromJson(Map<String, dynamic>.from(s as Map))];
    final quoted = sources.map((s) => CrossmatchPuzzle.normalise(s.excerpt)).join(' ');
    for (final tile in puzzle.tiles) {
      if (!quoted.contains(CrossmatchPuzzle.normalise(tile))) {
        throw FormatException('Crossmatch tile "$tile" is named in no source excerpt');
      }
    }
    final notes = item['editorNotes'];
    return CrossmatchItem(
      topic: topic,
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
/// The pick for a date is `fnv1a('crossmatch-<date>') % count`, stepped
/// forward past any file used within [reuseSpan] earlier dates, which are
/// computed the same way from [epoch], so a puzzle does not come round
/// again for at least thirty days. Adding a file to the reserve changes
/// later picks, which is fine: puzzle files are immutable once published and
/// the builder only writes dates it has not written before.
class CrossmatchGenerator {
  CrossmatchGenerator({this.reserveDir = defaultReserveDir}) {
    _load();
  }

  static const String slug = 'crossmatch';
  static const String defaultReserveDir = 'content_src/editorial/crossmatch';
  static const int minReserve = 30;
  static const int reuseWindow = 30;
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  final String reserveDir;
  final List<String> _files = [];
  final List<CrossmatchItem> _items = [];
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

  List<CrossmatchItem> get items => List.unmodifiable(_items);

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
        _items.add(CrossmatchItem.parse(json));
        _files.add(name);
      } on FormatException catch (e) {
        problems.add('$name: ${e.message}');
      }
    }
  }

  void _ensureReady() {
    if (problems.isNotEmpty) throw StateError('Crossmatch reserve has problems: ${problems.join('; ')}');
    if (_items.length < minReserve) {
      throw StateError('Crossmatch reserve has ${_items.length} puzzles; at least $minReserve are needed');
    }
  }

  /// The reserve index used on [date].
  int pickFor(DateTime date) {
    _ensureReady();
    final day = DateTime.utc(date.year, date.month, date.day);
    final cached = _picks[day];
    if (cached != null) return cached;
    var cursor = epoch;
    if (day.isBefore(epoch)) cursor = day;
    while (!cursor.isAfter(day)) {
      _picks.putIfAbsent(cursor, () => _pick(cursor));
      cursor = DateTime.utc(cursor.year, cursor.month, cursor.day + 1);
    }
    return _picks[day]!;
  }

  /// How many earlier dates a pick avoids. A reserve of exactly
  /// [reuseWindow] files cannot keep every file out of the previous
  /// [reuseWindow] dates, so the span stops one short of the reserve and
  /// the gap between two uses of a file is at least [reuseWindow] days.
  int get reuseSpan {
    _ensureReady();
    return reuseWindow < _items.length ? reuseWindow : _items.length - 1;
  }

  int _pick(DateTime day) {
    final count = _items.length;
    final span = reuseWindow < count ? reuseWindow : count - 1;
    final used = <int>{};
    for (var k = 1; k <= span; k++) {
      final earlier = DateTime.utc(day.year, day.month, day.day - k);
      if (earlier.isBefore(epoch)) break;
      final pick = _picks[earlier];
      if (pick != null) used.add(pick);
    }
    var index = seedFor(day) % count;
    while (used.contains(index)) {
      index = (index + 1) % count;
    }
    return index;
  }

  PuzzleRecord generate(DateTime date) {
    final index = pickFor(date);
    return _wrap(date, _items[index]);
  }

  /// The record for a news item carried by an edition template, validated
  /// exactly like a reserve file.
  PuzzleRecord fromTemplate(DateTime date, Map<String, dynamic> item, {String? storyId}) =>
      _wrap(date, CrossmatchItem.parse(item), storyId: storyId);

  PuzzleRecord _wrap(DateTime date, CrossmatchItem item, {String? storyId}) => PuzzleRecord(
        id: PuzzleId(game: GameKind.crossmatch, date: DateTime.utc(date.year, date.month, date.day)),
        locale: 'en-GB',
        contentVersion: 1,
        scoringVersion: 1,
        payload: item.payload,
        reveal: item.reveal,
        storyId: storyId,
        sources: item.sources,
      );
}
