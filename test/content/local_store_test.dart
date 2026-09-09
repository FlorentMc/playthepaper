import 'dart:io';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('word-2026-09-08-en-v1');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_store');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  test('progress is saved and cleared by a result', () async {
    await store.saveProgress(id, {'guesses': ['STREAM']});
    expect(store.progress(id)!['guesses'], ['STREAM']);
    expect(store.hasProgress(id), isTrue);
    await store.saveResult(GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: true, attempts: 2));
    expect(store.hasProgress(id), isFalse);
    expect(store.isCompleted(id), isTrue);
    expect(store.result(id)!.attempts, 2);
  });

  test('settings persist', () async {
    await store.updateSettings(themeMode: ThemeMode.dark, reducedMotion: true);
    expect(store.settings.themeMode, ThemeMode.dark);
    expect(store.settings.reducedMotion, isTrue);
    expect(store.settings.sudokuMistakeCheck, isTrue);
  });

  test('favourites toggle', () async {
    await store.toggleFavourite(GameKind.letters);
    expect(store.favourites, {GameKind.letters});
    await store.toggleFavourite(GameKind.letters);
    expect(store.favourites, isEmpty);
  });

  test('export and import merge without overwriting', () async {
    await store.saveResult(GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: true, attempts: 3));
    await store.toggleFavourite(GameKind.sudoku);
    final export = store.exportJson();

    await store.clearAll();
    await store.saveResult(GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: false, attempts: 6));
    final n = await store.importJson(export);
    expect(n, 0, reason: 'existing result must win');
    expect(store.result(id)!.solved, isFalse);
    expect(store.favourites, {GameKind.sudoku});

    await store.clearAll();
    expect(await store.importJson(export), 1);
    expect(store.result(id)!.attempts, 3);
  });

  test('import rejects foreign documents', () async {
    expect(() => store.importJson('{"hello": 1}'), throwsFormatException);
  });
}
