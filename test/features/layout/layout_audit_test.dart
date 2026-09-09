import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/features/play/game_registry.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../support/real_fonts.dart';

/// Opens real puzzles from content/ with the shipped fonts at the sizes and
/// text scales the QA audit used. Any RenderFlex overflow is reported by the
/// framework as a test exception, so a passing test means no clipping.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;

  setUpAll(() async {
    await loadRealFonts();
    dir = await Directory.systemTemp.createTemp('playthepaper_layout');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  PuzzleRecord record(String id) =>
      PuzzleRecord.fromJson(jsonDecode(File('content/puzzles/$id.json').readAsStringSync()) as Map<String, dynamic>);

  Future<void> pumpGame(WidgetTester tester, String id, {required Size size, double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final r = record(id);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
            child: child!,
          ),
          home: Builder(builder: (context) => GameRegistry.screens[r.game]!(context, PlayContext(store: store, record: r))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  const phone = Size(390, 844);
  const smallPhone = Size(320, 568);
  const landscape = Size(844, 390);

  final cases = <String, List<String>>{
    'crossword-2026-09-09-en-v1': ['phone', 'small', 'landscape', 'large text'],
    'word-2026-09-09-en-v1': ['phone', 'small', 'landscape', 'large text'],
    'sudoku-2026-09-09-en-easy-v1': ['phone', 'small', 'large text'],
    'nonogram-2026-09-09-en-v1': ['phone', 'small', 'large text'],
    'nonogram-2026-09-10-en-v1': ['phone', 'small', 'large text'],
    'letters-2026-09-09-en-v1': ['phone', 'small', 'large text'],
  };

  for (final entry in cases.entries) {
    for (final variant in entry.value) {
      testWidgets('${entry.key} lays out without overflow ($variant)', (tester) async {
        await tester.runAsync(() async {
          switch (variant) {
            case 'phone':
              await pumpGame(tester, entry.key, size: phone);
            case 'small':
              await pumpGame(tester, entry.key, size: smallPhone);
            case 'landscape':
              await pumpGame(tester, entry.key, size: landscape);
            case 'large text':
              await pumpGame(tester, entry.key, size: phone, textScale: 2.0);
          }
        });
      });
    }
  }
}
