import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/game_kind.dart';
import '../core/game_result.dart';
import '../core/puzzle_id.dart';

/// Player settings. Everything is optional and neutral by default.
class Settings extends ChangeNotifier {
  Settings({
    ThemeMode themeMode = ThemeMode.system,
    bool reducedMotion = false,
    bool sudokuMistakeCheck = true,
    bool showTimers = false,
  })  : _themeMode = themeMode,
        _reducedMotion = reducedMotion,
        _sudokuMistakeCheck = sudokuMistakeCheck,
        _showTimers = showTimers;

  ThemeMode _themeMode;
  bool _reducedMotion;
  bool _sudokuMistakeCheck;
  bool _showTimers;

  ThemeMode get themeMode => _themeMode;
  bool get reducedMotion => _reducedMotion;
  bool get sudokuMistakeCheck => _sudokuMistakeCheck;
  bool get showTimers => _showTimers;

  Map<String, dynamic> toJson() => {
        'themeMode': _themeMode.name,
        'reducedMotion': _reducedMotion,
        'sudokuMistakeCheck': _sudokuMistakeCheck,
        'showTimers': _showTimers,
      };

  static Settings fromJson(Map<String, dynamic> json) => Settings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        reducedMotion: json['reducedMotion'] as bool? ?? false,
        sudokuMistakeCheck: json['sudokuMistakeCheck'] as bool? ?? true,
        showTimers: json['showTimers'] as bool? ?? false,
      );

  void _apply(Settings other) {
    _themeMode = other._themeMode;
    _reducedMotion = other._reducedMotion;
    _sudokuMistakeCheck = other._sudokuMistakeCheck;
    _showTimers = other._showTimers;
  }
}

/// Every piece of player data, stored on the device only.
///
/// Boxes hold JSON strings so no type adapters are needed and the same data
/// can be exported and imported between the web and phone apps.
class LocalStore extends ChangeNotifier {
  LocalStore._();

  static const _progressBox = 'progress';
  static const _resultsBox = 'results';
  static const _prefsBox = 'prefs';
  static const _cacheBox = 'content_cache';

  late Box<String> _progress;
  late Box<String> _results;
  late Box<String> _prefs;
  late Box<String> _cache;

  final Settings settings = Settings();
  Set<GameKind> _favourites = {};

  static Future<LocalStore> open({String? subDir}) async {
    if (subDir != null) {
      Hive.init(subDir);
    } else {
      await Hive.initFlutter();
    }
    final store = LocalStore._();
    store._progress = await Hive.openBox<String>(_progressBox);
    store._results = await Hive.openBox<String>(_resultsBox);
    store._prefs = await Hive.openBox<String>(_prefsBox);
    store._cache = await Hive.openBox<String>(_cacheBox);
    store._loadPrefs();
    return store;
  }

  void _loadPrefs() {
    final raw = _prefs.get('settings');
    if (raw != null) {
      settings._apply(Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    final fav = _prefs.get('favourites');
    if (fav != null) {
      _favourites = (jsonDecode(fav) as List).map((s) => GameKind.fromSlug(s as String)).toSet();
    }
  }

  // ---------------------------------------------------------------- progress

  /// In-progress state for a puzzle, or null when it has not been started.
  Map<String, dynamic>? progress(PuzzleId id) {
    final raw = _progress.get(id.toString());
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  bool hasProgress(PuzzleId id) => _progress.containsKey(id.toString());

  Future<void> saveProgress(PuzzleId id, Map<String, dynamic> state) async {
    await _progress.put(id.toString(), jsonEncode(state));
    notifyListeners();
  }

  Future<void> clearProgress(PuzzleId id) async {
    await _progress.delete(id.toString());
    notifyListeners();
  }

  // ----------------------------------------------------------------- results

  GameResult? result(PuzzleId id) {
    final raw = _results.get(id.toString());
    return raw == null ? null : GameResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  bool isCompleted(PuzzleId id) => _results.containsKey(id.toString());

  Future<void> saveResult(GameResult result) async {
    await _results.put(result.puzzleId.toString(), jsonEncode(result.toJson()));
    await _progress.delete(result.puzzleId.toString());
    notifyListeners();
  }

  List<GameResult> allResults() =>
      _results.values.map((r) => GameResult.fromJson(jsonDecode(r) as Map<String, dynamic>)).toList();

  List<GameResult> resultsFor(GameKind game) => allResults().where((r) => r.game == game).toList();

  // -------------------------------------------------------------- favourites

  Set<GameKind> get favourites => Set.unmodifiable(_favourites);

  Future<void> toggleFavourite(GameKind game) async {
    if (!_favourites.remove(game)) _favourites.add(game);
    await _prefs.put('favourites', jsonEncode(_favourites.map((g) => g.slug).toList()));
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings

  Future<void> updateSettings({
    ThemeMode? themeMode,
    bool? reducedMotion,
    bool? sudokuMistakeCheck,
    bool? showTimers,
  }) async {
    settings._apply(Settings(
      themeMode: themeMode ?? settings.themeMode,
      reducedMotion: reducedMotion ?? settings.reducedMotion,
      sudokuMistakeCheck: sudokuMistakeCheck ?? settings.sudokuMistakeCheck,
      showTimers: showTimers ?? settings.showTimers,
    ));
    await _prefs.put('settings', jsonEncode(settings.toJson()));
    settings.notifyListeners();
    notifyListeners();
  }

  // ---------------------------------------------------------------- extras

  /// Small game-specific local state that is not tied to a puzzle id, such
  /// as the unlimited 2048 board or a best score. Namespaced by [key].
  String? extra(String key) => _prefs.get('extra:$key');

  Future<void> setExtra(String key, String? value) async {
    if (value == null) {
      await _prefs.delete('extra:$key');
    } else {
      await _prefs.put('extra:$key', value);
    }
    notifyListeners();
  }

  // ----------------------------------------------------------- content cache

  String? cached(String key) => _cache.get(key);

  Future<void> cache(String key, String json) => _cache.put(key, json);

  // ----------------------------------------------------------- export/import

  /// Everything a player owns, as a single JSON document.
  String exportJson() => jsonEncode({
        'format': 'playthepaper-export',
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'progress': {for (final k in _progress.keys) k: jsonDecode(_progress.get(k)!)},
        'results': {for (final k in _results.keys) k: jsonDecode(_results.get(k)!)},
        'settings': settings.toJson(),
        'favourites': _favourites.map((g) => g.slug).toList(),
      });

  /// Merges an export into this device. Existing results win over imported
  /// ones for the same puzzle so a replay never overwrites a real completion.
  Future<int> importJson(String raw) async {
    final json = jsonDecode(raw);
    if (json is! Map || json['format'] != 'playthepaper-export') {
      throw const FormatException('Not a Play the Paper export');
    }
    var imported = 0;
    final results = json['results'];
    if (results is Map) {
      for (final entry in results.entries) {
        final id = PuzzleId.tryParse(entry.key as String);
        if (id == null || _results.containsKey(entry.key)) continue;
        final result = GameResult.fromJson(Map<String, dynamic>.from(entry.value as Map));
        await _results.put(entry.key as String, jsonEncode(result.toJson()));
        imported++;
      }
    }
    final progress = json['progress'];
    if (progress is Map) {
      for (final entry in progress.entries) {
        final key = entry.key as String;
        if (PuzzleId.tryParse(key) == null || _results.containsKey(key) || _progress.containsKey(key)) continue;
        await _progress.put(key, jsonEncode(entry.value));
        imported++;
      }
    }
    final fav = json['favourites'];
    if (fav is List) {
      for (final slug in fav) {
        final g = GameKind.values.where((k) => k.slug == slug).firstOrNull;
        if (g != null) _favourites.add(g);
      }
      await _prefs.put('favourites', jsonEncode(_favourites.map((g) => g.slug).toList()));
    }
    notifyListeners();
    return imported;
  }

  @visibleForTesting
  Future<void> clearAll() async {
    await _progress.clear();
    await _results.clear();
    await _prefs.clear();
    await _cache.clear();
    _favourites = {};
    notifyListeners();
  }
}
