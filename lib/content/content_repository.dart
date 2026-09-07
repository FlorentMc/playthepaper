import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:http/http.dart' as http;

import '../core/edition_clock.dart';
import '../core/puzzle_id.dart';
import '../storage/local_store.dart';
import 'models.dart';

/// Where published content lives on the web. The same paths exist inside the
/// app bundle under `assets/content/`.
const String kContentBaseUrl = 'https://daypencil.com/content';

class ContentNotFound implements Exception {
  const ContentNotFound(this.what);
  final String what;
  @override
  String toString() => 'Content not found: $what';
}

/// Loads editions and puzzles from, in order of preference for the current
/// date: the network, the local cache, the bundled starter content. Puzzles
/// are immutable by id, so any copy is as good as any other.
class ContentRepository {
  ContentRepository({
    required LocalStore store,
    http.Client? client,
    AssetBundle? bundle,
    this.baseUrl = kContentBaseUrl,
    this.networkTimeout = const Duration(seconds: 6),
  })  : _store = store,
        _client = client ?? http.Client(),
        _bundle = bundle ?? rootBundle;

  final LocalStore _store;
  final http.Client _client;
  final AssetBundle _bundle;
  final String baseUrl;
  final Duration networkTimeout;

  /// Set to false in tests or when offline to skip network attempts.
  bool networkEnabled = true;

  Future<String?> _fromNetwork(String path) async {
    if (!networkEnabled) return null;
    try {
      final response = await _client.get(Uri.parse('$baseUrl/$path')).timeout(networkTimeout);
      if (response.statusCode == 200) return utf8.decode(response.bodyBytes);
    } catch (e) {
      debugPrint('content: network miss for $path ($e)');
    }
    return null;
  }

  Future<String?> _fromBundle(String path) async {
    try {
      return await _bundle.loadString('assets/content/$path');
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decode(String raw, String what) {
    final json = jsonDecode(raw);
    if (json is Map<String, dynamic>) return json;
    throw FormatException('$what is not a JSON object');
  }

  /// The bundled index plus anything the network knows about.
  Future<ContentIndex> index() async {
    final local = await _fromBundle('index.json');
    final remote = await _fromNetwork('index.json');
    final dates = <DateTime>{};
    DateTime? latest;
    for (final raw in [local, remote]) {
      if (raw == null) continue;
      try {
        final idx = ContentIndex.fromJson(_decode(raw, 'index'));
        dates.addAll(idx.dates);
        if (latest == null || idx.latest.isAfter(latest)) latest = idx.latest;
      } on FormatException catch (e) {
        debugPrint('content: bad index ($e)');
      }
    }
    // Cached editions count too: a player may have downloaded a date the
    // bundle does not contain.
    for (final key in _cachedEditionDates()) {
      dates.add(key);
    }
    if (dates.isEmpty) throw const ContentNotFound('index');
    final sorted = dates.toList()..sort();
    return ContentIndex(dates: sorted, latest: latest ?? sorted.last);
  }

  Iterable<DateTime> _cachedEditionDates() sync* {
    final raw = _store.cached('edition_dates');
    if (raw == null) return;
    for (final d in jsonDecode(raw) as List) {
      yield EditionClock.parseDate(d as String);
    }
  }

  Future<void> _rememberEditionDate(DateTime date) async {
    final dates = _cachedEditionDates().toSet()..add(date);
    await _store.cache('edition_dates', jsonEncode(dates.map(EditionClock.formatDate).toList()));
  }

  /// The edition for [date]. For today's date the network is tried first so a
  /// news edition can replace a prepared evergreen one; older dates prefer
  /// the cache because they never change.
  Future<EditionManifest> edition(DateTime date, {bool preferNetwork = false}) async {
    final key = EditionClock.formatDate(date);
    final path = 'editions/$key.json';
    final cacheKey = 'edition:$key';

    Future<EditionManifest?> parse(String? raw, String origin) async {
      if (raw == null) return null;
      try {
        final manifest = EditionManifest.fromJson(_decode(raw, 'edition $key'));
        if (manifest.date != date) throw FormatException('edition file for $key has date ${manifest.dateString}');
        return manifest;
      } on FormatException catch (e) {
        debugPrint('content: bad edition from $origin ($e)');
        return null;
      }
    }

    EditionManifest? best;
    if (preferNetwork) {
      best = await parse(await _fromNetwork(path), 'network');
      if (best != null) {
        await _store.cache(cacheKey, jsonEncode(best.toJson()));
        await _rememberEditionDate(date);
        return best;
      }
    }
    best = await parse(_store.cached(cacheKey), 'cache');
    if (best != null) return best;
    best = await parse(await _fromBundle(path), 'bundle');
    if (best != null) return best;
    if (!preferNetwork) {
      best = await parse(await _fromNetwork(path), 'network');
      if (best != null) {
        await _store.cache(cacheKey, jsonEncode(best.toJson()));
        await _rememberEditionDate(date);
        return best;
      }
    }
    throw ContentNotFound('edition $key');
  }

  Future<PuzzleRecord> puzzle(PuzzleId id) async {
    final key = id.toString();
    final cacheKey = 'puzzle:$key';
    final path = 'puzzles/$key.json';

    PuzzleRecord? parse(String? raw, String origin) {
      if (raw == null) return null;
      try {
        final record = PuzzleRecord.fromJson(_decode(raw, 'puzzle $key'));
        if (record.id != id) throw FormatException('puzzle file $key contains ${record.id}');
        return record;
      } on FormatException catch (e) {
        debugPrint('content: bad puzzle from $origin ($e)');
        return null;
      }
    }

    var record = parse(_store.cached(cacheKey), 'cache');
    if (record != null) return record;
    record = parse(await _fromBundle(path), 'bundle');
    if (record != null) return record;
    final raw = await _fromNetwork(path);
    record = parse(raw, 'network');
    if (record != null) {
      await _store.cache(cacheKey, raw!);
      return record;
    }
    throw ContentNotFound('puzzle $key');
  }

  /// Fetches every puzzle of an edition so it can be played offline.
  Future<List<PuzzleRecord>> preloadEdition(EditionManifest manifest) async {
    final records = <PuzzleRecord>[];
    for (final id in manifest.puzzles) {
      try {
        records.add(await puzzle(id));
      } on ContentNotFound catch (e) {
        debugPrint('content: preload skipped $e');
      }
    }
    return records;
  }
}

/// Holds the current edition for the UI and refreshes it across the 04:00
/// UTC boundary.
class EditionController extends ChangeNotifier {
  EditionController({required ContentRepository repository, EditionClock clock = const EditionClock()})
      : _repository = repository,
        _clock = clock;

  final ContentRepository _repository;
  final EditionClock _clock;

  EditionManifest? _today;
  Object? _error;
  bool _loading = false;
  Timer? _rollover;

  EditionManifest? get today => _today;
  Object? get error => _error;
  bool get loading => _loading;
  DateTime get todayDate => _clock.today();
  ContentRepository get repository => _repository;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final date = _clock.today();
    try {
      _today = await _repository.edition(date, preferNetwork: true);
      unawaited(_repository.preloadEdition(_today!));
    } on ContentNotFound {
      // Fall back to the latest edition we do have, clearly dated.
      try {
        final idx = await _repository.index();
        final latest = idx.dates.where((d) => !d.isAfter(date)).lastOrNull ?? idx.dates.last;
        _today = await _repository.edition(latest);
      } catch (e) {
        _error = e;
      }
    } catch (e) {
      _error = e;
    }
    _loading = false;
    notifyListeners();
    _scheduleRollover();
  }

  void _scheduleRollover() {
    _rollover?.cancel();
    final wait = _clock.untilNextEdition() + const Duration(seconds: 2);
    _rollover = Timer(wait, load);
  }

  @override
  void dispose() {
    _rollover?.cancel();
    super.dispose();
  }
}
