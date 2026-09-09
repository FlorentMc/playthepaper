import 'dart:convert';
import 'dart:io';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'groups_puzzle.dart';

/// One written puzzle from the evergreen reserve or a news template:
/// `{"topic", "payload", "reveal", "sources", "editorNotes"}`.
class GroupsItem {
  const GroupsItem({
    required this.topic,
    required this.puzzle,
    required this.sources,
    this.editorNotes,
  });

  final String topic;
  final GroupsPuzzle puzzle;
  final List<SourceRef> sources;

  /// The alternative groupings the editor checked and why they do not fit.
  final String? editorNotes;

  /// True when [excerpt], already normalised, names [tile] as a word of its
  /// own rather than inside a longer one, so "Mersey" is not carried by
  /// "Merseybeat". A trailing plural is allowed.
  static bool names(String tile, String excerpt) =>
      RegExp('(^| )${RegExp.escape(GroupsPuzzle.normalise(tile))}(s|es)?( |\$)').hasMatch(excerpt);

  /// Parses and checks an item. Beyond the engine rules: every tile must
  /// appear in a cited excerpt, so no word ships unsourced, and at most one
  /// tile may be declared as plausibly fitting a second group.
  static GroupsItem parse(Map<String, dynamic> item) {
    final payload = item['payload'];
    final reveal = item['reveal'];
    if (payload is! Map || reveal is! Map) throw const FormatException('Groups item needs "payload" and "reveal"');
    final puzzle = GroupsPuzzle.parse(Map<String, dynamic>.from(payload), Map<String, dynamic>.from(reveal));
    final rawTopic = item['topic'];
    if (rawTopic is! String || rawTopic.trim().isEmpty) throw const FormatException('Groups item needs a "topic"');
    final rawSources = item['sources'];
    if (rawSources is! List || rawSources.isEmpty) throw const FormatException('Groups item needs "sources"');
    final sources = [for (final s in rawSources) SourceRef.fromJson(Map<String, dynamic>.from(s as Map))];
    final excerpts = sources.map((s) => GroupsPuzzle.normalise(s.excerpt)).toList();
    for (final tile in puzzle.tiles) {
      if (!excerpts.any((e) => names(tile, e))) {
        throw FormatException('Groups tile "$tile" is named in no source excerpt');
      }
    }
    final overlap = {
      for (final group in puzzle.groups) ...group.alsoFits.map(GroupsPuzzle.normalise),
    };
    if (overlap.length > 1) {
      throw FormatException('Groups item "$rawTopic" declares ${overlap.length} overlapping tiles; at most one is fair');
    }
    final notes = item['editorNotes'];
    if (notes is! String || notes.trim().isEmpty) {
      throw FormatException('Groups item "$rawTopic" needs "editorNotes" recording the groupings you ruled out');
    }
    return GroupsItem(
      topic: rawTopic.trim(),
      puzzle: puzzle,
      sources: sources,
      editorNotes: notes.trim(),
    );
  }
}

/// Picks a reserve puzzle for each date, lays its tiles out for that date and
/// wraps it in the record envelope.
///
/// The pick for a date is `fnv1a('groups-<date>') % count`, stepped forward
/// past any file used on the previous thirty dates, which are computed the
/// same way from [epoch]. The board is then shuffled from the same seed, so
/// every player of that date sees the same layout; seeds are tried in turn
/// until the layout passes the engine's own parse, which rejects a row of
/// four that gives a group away.
class GroupsGenerator {
  GroupsGenerator({this.reserveDir = defaultReserveDir}) {
    _load();
  }

  static const String slug = 'groups';
  static const String defaultReserveDir = 'content_src/editorial/groups';
  static const int minReserve = 30;
  static const int reuseWindow = 30;
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  final String reserveDir;
  final List<String> _files = [];
  final List<GroupsItem> _items = [];
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

  List<GroupsItem> get items => List.unmodifiable(_items);

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
        _items.add(GroupsItem.parse(json));
        _files.add(name);
      } on FormatException catch (e) {
        problems.add('$name: ${e.message}');
      }
    }
  }

  void _ensureReady() {
    if (problems.isNotEmpty) throw StateError('Groups reserve has problems: ${problems.join('; ')}');
    if (_items.length < minReserve) {
      throw StateError('Groups reserve has ${_items.length} puzzles; at least $minReserve are needed');
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

  int _pick(DateTime day) {
    final count = _items.length;
    final used = <int>{};
    for (var k = 1; k <= reuseWindow; k++) {
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

  PuzzleRecord generate(DateTime date) {
    final index = pickFor(date);
    return _wrap(date, _items[index]);
  }

  /// The record for a news item carried by an edition template, validated
  /// exactly like a reserve file.
  PuzzleRecord fromTemplate(DateTime date, Map<String, dynamic> item, {String? storyId}) =>
      _wrap(date, GroupsItem.parse(item), storyId: storyId);

  /// The board [item] shows on [date]: the tiles shuffled from the date's
  /// seed, trying the next seed until the engine accepts the layout.
  static GroupsPuzzle layoutFor(DateTime date, GroupsPuzzle puzzle) {
    final base = seedFor(date);
    for (var attempt = 0; attempt < 64; attempt++) {
      final order = _shuffled(puzzle.tiles, fnv1a('$base:$attempt'));
      final candidate = puzzle.withTiles(order);
      try {
        return GroupsPuzzle.parse(candidate.toPayload(), candidate.toReveal());
      } on FormatException {
        continue;
      }
    }
    throw StateError('No fair layout found for ${EditionClock.formatDate(date)}');
  }

  static List<String> _shuffled(List<String> items, int seed) {
    final out = List<String>.of(items);
    var state = seed == 0 ? 1 : seed;
    for (var i = out.length - 1; i > 0; i--) {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      final j = state % (i + 1);
      final tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }

  PuzzleRecord _wrap(DateTime date, GroupsItem item, {String? storyId}) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final laid = layoutFor(day, item.puzzle);
    return PuzzleRecord(
      id: PuzzleId(game: GameKind.groups, date: day),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: laid.toPayload(),
      reveal: laid.toReveal(),
      storyId: storyId,
      sources: item.sources,
    );
  }
}
