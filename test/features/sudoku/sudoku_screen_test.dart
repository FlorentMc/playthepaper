import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/core/theme.dart';
import 'package:daypencil/engines/sudoku/sudoku.dart';
import 'package:daypencil/features/games/sudoku/sudoku_screen.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O can only complete with a real
/// event loop. Left in the fake-async zone, a pending write would hold the
/// box lock and deadlock the next test's clear.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('sudoku-2026-09-08-en-easy-v1');
  final puzzle = SudokuGenerator.generate(seed: SudokuGenerator.seedFor('2026-09-08', Difficulty.easy), difficulty: Difficulty.easy);
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: puzzle.toPayload(),
    reveal: puzzle.toReveal(),
  );
  final blank = puzzle.givens.indexOf(0);
  final answer = puzzle.solution[blank];
  final wrong = answer == 9 ? 1 : answer + 1;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('daypencil_sudoku');
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
          theme: DaypencilTheme.light(),
          home: SudokuScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder cell(int index) => find.byKey(ValueKey('sudoku-cell-$index'));
  Finder key(int digit) => find.byKey(ValueKey('sudoku-key-$digit'));
  Finder cellText(int index, String text) => find.descendant(of: cell(index), matching: find.text(text));

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('renders 81 cells and places a tapped number', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 81; i++) {
        expect(cell(i), findsOneWidget, reason: 'cell $i');
      }
      for (var d = 1; d <= 9; d++) {
        expect(key(d), findsOneWidget);
      }
      expect(cellText(blank, '$answer'), findsNothing);

      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, key(answer));

      expect(cellText(blank, '$answer'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('Mistakes 0'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((store.progress(id)!['values'] as String)[blank], '$answer');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a wrong entry is marked with a cross when mistake check is on', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, key(wrong));
      expect(cellText(blank, '$wrong'), findsOneWidget);
      expect(find.descendant(of: cell(blank), matching: find.byIcon(Icons.close)), findsOneWidget);
      expect(find.text('Mistakes 1'), findsOneWidget);

      await tapThenPump(tester, find.byKey(const ValueKey('sudoku-undo')));
      expect(cellText(blank, '$wrong'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('Mistakes 1'), findsOneWidget);
      await tapThenPump(tester, find.byKey(const ValueKey('sudoku-redo')));
      expect(cellText(blank, '$wrong'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('notes mode pencils digits and the physical keyboard works', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('Notes off'), findsOneWidget);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, find.byKey(const ValueKey('sudoku-notes')));
      expect(find.text('Notes on'), findsOneWidget);
      await tapThenPump(tester, key(3));
      expect(cellText(blank, '3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(find.text('Notes off'), findsOneWidget);
      await tester.sendKeyEvent(_digitKey(answer));
      await tester.pump();
      expect(cellText(blank, '$answer'), findsOneWidget);
      expect(cellText(blank, '3'), findsNothing);

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
        GameResult(puzzleId: id, completedAt: DateTime.utc(2026, 9, 8), solved: true, seconds: 300, hints: 1),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(key(1), findsNothing);
      expect(cellText(blank, '$answer'), findsOneWidget);
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Grid complete'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('filling the last cell completes the puzzle once', (tester) async {
    await tester.runAsync(() async {
      var state = SudokuState.initial(puzzle);
      for (var i = 0; i < 81; i++) {
        if (!puzzle.isGiven(i) && i != blank) state = state.select(i).setValue(puzzle.solution[i]);
      }
      await store.saveProgress(id, state.tick(42).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      await tapThenPump(tester, cell(blank));
      await tapThenPump(tester, key(answer));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Grid complete').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      expect(find.text('Grid complete'), findsOneWidget);
      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 42);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
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
      5 => LogicalKeyboardKey.digit5,
      6 => LogicalKeyboardKey.digit6,
      7 => LogicalKeyboardKey.digit7,
      8 => LogicalKeyboardKey.digit8,
      _ => LogicalKeyboardKey.digit9,
    };
