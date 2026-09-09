import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'uncover_puzzle.dart';

/// One file of the evergreen reserve, `content_src/editorial/uncover/NNN.json`.
class UncoverReserveItem {
  const UncoverReserveItem({
    required this.file,
    required this.topic,
    required this.payload,
    required this.reveal,
    required this.sources,
    this.editorNotes,
  });

  final String file;
  final String topic;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> reveal;
  final List<SourceRef> sources;
  final String? editorNotes;

  String get subject => reveal['subject'] as String;
}

/// Picks the day's Uncover puzzle from the evergreen reserve, or wraps a
/// news item from an edition template. Reserve picks are deterministic:
/// the base pick for a date is `fnv1a('uncover-<date>') % count`, bumped
/// to the next file while it repeats a pick of the previous [avoidWindow]
/// dates, walking forward from [epoch] so every date's pick is fixed.
///
/// Reads the reserve with `dart:io`; only the content tools and tests call
/// it, never the app.
class UncoverGenerator {
  UncoverGenerator({this.reserveDir = defaultReserveDir});

  static const String defaultReserveDir = 'content_src/editorial/uncover';
  static const int avoidWindow = 30;

  /// The first content date; picks before it are base picks.
  static final DateTime epoch = DateTime.utc(2026, 9, 1);

  final String reserveDir;
  List<UncoverReserveItem>? _reserve;

  /// Stable 32-bit FNV-1a hash, the same as the content tools use.
  static int fnv1a(String input) {
    var hash = 0x811C9DC5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static int basePick(DateTime date, int count) => fnv1a('uncover-${EditionClock.formatDate(date)}') % count;

  /// The reserve index for [date] among [count] files.
  static int pickFor(DateTime date, int count) {
    if (count <= 0) throw ArgumentError.value(count, 'count', 'must be positive');
    final window = min(avoidWindow, count - 1);
    if (window <= 0 || date.isBefore(epoch)) return basePick(date, count);
    final recent = <int>[];
    var d = epoch.subtract(Duration(days: window));
    while (!d.isAfter(date)) {
      var pick = basePick(d, count);
      if (!d.isBefore(epoch)) {
        while (recent.contains(pick)) {
          pick = (pick + 1) % count;
        }
      }
      recent.add(pick);
      if (recent.length > window) recent.removeAt(0);
      d = d.add(const Duration(days: 1));
    }
    return recent.last;
  }

  /// The reserve, sorted by file name. Throws [FormatException] naming the
  /// first file that fails to parse; see [checkReserve] for all of them.
  List<UncoverReserveItem> get reserve {
    final loaded = _reserve;
    if (loaded != null) return loaded;
    final items = <UncoverReserveItem>[];
    for (final file in _reserveFiles()) {
      try {
        items.add(_readItem(file));
      } on FormatException catch (e) {
        throw FormatException('${file.path}: ${e.message}');
      }
    }
    if (items.isEmpty) throw FormatException('No Uncover reserve files in $reserveDir');
    return _reserve = List.unmodifiable(items);
  }

  /// Every reserve file that fails to parse, with its error.
  Map<String, String> checkReserve() {
    final problems = <String, String>{};
    for (final file in _reserveFiles()) {
      try {
        _readItem(file);
      } on FormatException catch (e) {
        problems[file.path] = e.message;
      }
    }
    return problems;
  }

  List<File> _reserveFiles() {
    final dir = Directory(reserveDir);
    if (!dir.existsSync()) throw FormatException('Uncover reserve directory not found: $reserveDir');
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static UncoverReserveItem _readItem(File file) {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, dynamic>) throw const FormatException('not a JSON object');
    final topic = json['topic'];
    if (topic is! String || topic.isEmpty) throw const FormatException('missing "topic"');
    final payload = json['payload'];
    final reveal = json['reveal'];
    if (payload is! Map<String, dynamic>) throw const FormatException('missing "payload"');
    if (reveal is! Map<String, dynamic>) throw const FormatException('missing "reveal"');
    UncoverPuzzle.parse(payload, reveal);
    final rawSources = json['sources'];
    if (rawSources is! List || rawSources.isEmpty) throw const FormatException('missing "sources"');
    final sources = rawSources.map((s) {
      if (s is! Map<String, dynamic>) throw const FormatException('source must be an object');
      return SourceRef.fromJson(s);
    }).toList();
    final notes = json['editorNotes'];
    if (notes != null && notes is! String) throw const FormatException('"editorNotes" must be a string');
    return UncoverReserveItem(
      file: file.uri.pathSegments.last,
      topic: topic,
      payload: payload,
      reveal: reveal,
      sources: sources,
      editorNotes: notes as String?,
    );
  }

  /// The reserve item chosen for [date].
  UncoverReserveItem itemFor(DateTime date) => reserve[pickFor(date, reserve.length)];

  PuzzleRecord generate(DateTime date) {
    final item = itemFor(date);
    return _record(date, item.payload, item.reveal, sources: item.sources);
  }

  /// Wraps a news item `{"payload", "reveal", "sources"}` from an edition
  /// template. A payload without `text` gets it derived from the reveal.
  PuzzleRecord fromTemplate(DateTime date, Map<String, dynamic> item, {String? storyId}) {
    final rawPayload = item['payload'];
    final rawReveal = item['reveal'];
    if (rawPayload is! Map) throw const FormatException('Uncover template item is missing "payload"');
    if (rawReveal is! Map) throw const FormatException('Uncover template item is missing "reveal"');
    final payload = Map<String, dynamic>.from(rawPayload);
    final reveal = Map<String, dynamic>.from(rawReveal);
    payload['text'] ??= UncoverPuzzle.maskedTextFor(reveal);
    final rawSources = item['sources'];
    final sources = rawSources is List
        ? rawSources.map((s) => SourceRef.fromJson(Map<String, dynamic>.from(s as Map))).toList()
        : const <SourceRef>[];
    return _record(date, payload, reveal, sources: sources, storyId: storyId);
  }

  static PuzzleRecord _record(
    DateTime date,
    Map<String, dynamic> payload,
    Map<String, dynamic> reveal, {
    required List<SourceRef> sources,
    String? storyId,
  }) {
    final puzzle = UncoverPuzzle.parse(payload, reveal);
    final record = PuzzleRecord(
      id: PuzzleId(game: GameKind.uncover, date: date),
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
      storyId: storyId,
      sources: sources,
    );
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    final parsed = UncoverPuzzle.parse(check.payload, check.reveal);
    if (parsed.maskedText != puzzle.maskedText || parsed.subject != puzzle.subject) {
      throw StateError('Round trip failed for ${record.id}');
    }
    return record;
  }
}
