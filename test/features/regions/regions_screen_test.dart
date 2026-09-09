import 'dart:io';

import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/regions/regions.dart';
import 'package:playthepaper/features/games/regions/regions_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O can only complete with a real
/// event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final record = RegionsGenerator().generate(DateTime.utc(2026, 9, 10));
  final id = record.id;
  final puzzle = RegionsPuzzle.parse(record.payload, record.reveal);
  final blank = List.generate(puzzle.cellCount, (i) => i).firstWhere((i) => !puzzle.isGiven(i) && puzzle.grid.sizeOf(i) >= 2);
  final answer = puzzle.solution[blank];
  final wrong = answer == 1 ? 2 : 1;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_regions');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  /// The game timer schedules a frame every second, so pumpAndSettle would
  /// never return while play is in progress.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpScreen(WidgetTester tester, {bool isArchivePlay = false}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: RegionsScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
        ),
      ),
    );
    await settle(tester);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(400, 20));
      await settle(tester);
    }
    expect(find.byType(BottomSheet), findsNothing, reason: 'the first-run help sheet must be dismissed');
  }

  Future<void> tearDownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Finder cell(int index) => find.byKey(ValueKey('regions-cell-$index'));
  Finder key(int digit) => find.byKey(ValueKey('regions-key-$digit'));
  Finder cellText(int index, String text) => find.descendant(of: cell(index), matching: find.text(text));

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('renders 36 cells and places a tapped number', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 36; i++) {
        expect(cell(i), findsOneWidget, reason: 'cell $i');
      }
      for (var d = 1; d <= puzzle.grid.maxDigit; d++) {
        expect(key(d), findsOneWidget);
      }
      expect(key(6), findsNothing);
      expect(cellText(blank, '$answer'), findsNothing);

      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, key(answer));

      expect(cellText(blank, '$answer'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((store.progress(id)!['values'] as String)[blank], '$answer');
      await tearDownScreen(tester);
    });
  });

  testWidgets('check marks a wrong digit with a cross and counts a hint; undo removes it', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, key(wrong));
      expect(cellText(blank, '$wrong'), findsOneWidget);
      await tapThenPump(tester, find.byKey(const ValueKey('regions-check')));
      expect(find.descendant(of: cell(blank), matching: find.byIcon(Icons.close)), findsOneWidget);
      expect(find.text('1 hint'), findsOneWidget);
      expect(find.text('1 wrong digit marked.'), findsOneWidget);

      await tapThenPump(tester, find.byKey(const ValueKey('regions-undo')));
      expect(cellText(blank, '$wrong'), findsNothing);
      expect(find.descendant(of: cell(blank), matching: find.byIcon(Icons.close)), findsNothing);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['hints'], 1);
      await tearDownScreen(tester);
    });
  });

  testWidgets('notes mode pencils digits and the physical keyboard works', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('Notes off'), findsOneWidget);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, find.byKey(const ValueKey('regions-notes')));
      expect(find.text('Notes on'), findsOneWidget);
      await tapThenPump(tester, key(1));
      expect(cellText(blank, '1'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(find.text('Notes off'), findsOneWidget);
      await tester.sendKeyEvent(_digitKey(answer));
      await tester.pump();
      expect(cellText(blank, '$answer'), findsOneWidget);
      if (answer != 1) expect(cellText(blank, '1'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(cellText(blank, '$answer'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(_digitKey(answer));
      await tester.pump();
      expect(cellText(blank, '$answer'), findsOneWidget, reason: 'arrows move the selection and back');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.pump();
      expect(cellText(blank, '$answer'), findsNothing, reason: 'U undoes');
      await tearDownScreen(tester);
    });
  });

  testWidgets('the timer counts while playing and is shown only when enabled', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      await store.updateSettings(showTimers: true);
      await tester.pump();
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await tester.pump();
      expect(find.text('0:02'), findsOneWidget);
      await store.updateSettings(showTimers: false);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle is read-only with a See result button', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(puzzleId: id, completedAt: DateTime.utc(2026, 9, 10), solved: true, seconds: 300, hints: 1),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(key(1), findsNothing);
      expect(find.byKey(const ValueKey('regions-check')), findsNothing);
      expect(cellText(blank, '$answer'), findsOneWidget);
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Solved'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('filling the last cell completes the puzzle once', (tester) async {
    await tester.runAsync(() async {
      var state = RegionsState.initial(puzzle);
      for (var i = 0; i < puzzle.cellCount; i++) {
        if (!puzzle.isGiven(i) && i != blank) state = state.select(i).setValue(puzzle.solution[i]);
      }
      await store.saveProgress(id, state.tick(42).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, key(answer));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Solved').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 42);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines.length, 6);
      expect(result.shareLines.join().contains('⬜'), isFalse);
      expect(store.hasProgress(id), isFalse);
      await tearDownScreen(tester);
    });
  });
}

LogicalKeyboardKey _digitKey(int digit) => switch (digit) {
      1 => LogicalKeyboardKey.digit1,
      2 => LogicalKeyboardKey.digit2,
      3 => LogicalKeyboardKey.digit3,
      4 => LogicalKeyboardKey.digit4,
      _ => LogicalKeyboardKey.digit5,
    };
