import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:playthepaper/features/games/kakuro/kakuro_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../engines/kakuro/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O can only complete with a real
/// event loop. Left in the fake-async zone, a pending write would hold the
/// box lock and deadlock the next test's clear.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;

  final dailyId = PuzzleId.parse('kakuro-2026-09-10-en-v1');
  final daily = KakuroGenerator().generate(DateTime.utc(2026, 9, 10));
  final dailyPuzzle = KakuroPuzzle.parse(daily.payload, daily.reveal);
  final first = dailyPuzzle.whiteCells.first;
  final answer = dailyPuzzle.solution[first];
  final wrong = answer == 9 ? 1 : answer + 1;

  final smallId = PuzzleId.parse('kakuro-2026-09-11-en-v1');
  final small = PuzzleRecord(
    id: smallId,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: smallPayload(),
    reveal: smallReveal(),
  );
  final smallPuzzle = KakuroPuzzle.parse(small.payload, small.reveal);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_kakuro');
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

  Future<void> pumpScreen(WidgetTester tester, PuzzleRecord record, {bool isArchivePlay = false}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: KakuroScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder cell(int index) => find.byKey(ValueKey('kakuro-cell-$index'));
  Finder key(int digit) => find.byKey(ValueKey('kakuro-key-$digit'));
  Finder cellText(int index, String text) => find.descendant(of: cell(index), matching: find.text(text));

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('renders every cell and places a tapped number, saving progress', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, daily);
      for (var i = 0; i < 36; i++) {
        expect(cell(i), findsOneWidget, reason: 'cell $i');
      }
      for (var d = 1; d <= 9; d++) {
        expect(key(d), findsOneWidget);
      }
      expect(find.text('Tap a white cell to begin.'), findsOneWidget);
      expect(cellText(first, '$answer'), findsNothing);

      await tapThenPump(tester, key(answer));
      expect(cellText(first, '$answer'), findsNothing, reason: 'no cell selected yet');

      await tapThenPump(tester, cell(first));
      final runs = dailyPuzzle.grid.runsThrough(first);
      expect(find.text('${runs[0].sum} across in ${runs[0].length} · ${runs[1].sum} down in ${runs[1].length}'), findsOneWidget);
      await tapThenPump(tester, key(answer));

      expect(cellText(first, '$answer'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((store.progress(dailyId)!['values'] as List)[first], answer);
      await tearDownScreen(tester);
    });
  });

  testWidgets('check marks a wrong digit with a cross and counts a hint; undo and redo work', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, daily);
      await tapThenPump(tester, cell(first));
      await tapThenPump(tester, key(wrong));
      expect(cellText(first, '$wrong'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);

      await tapThenPump(tester, find.byKey(const ValueKey('kakuro-check')));
      expect(find.descendant(of: cell(first), matching: find.byIcon(Icons.close)), findsOneWidget);
      expect(find.text('1 hint'), findsOneWidget);
      expect(find.text('1 wrong digit marked.'), findsOneWidget);

      await tapThenPump(tester, find.byKey(const ValueKey('kakuro-undo')));
      expect(cellText(first, '$wrong'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('1 hint'), findsOneWidget);
      await tapThenPump(tester, find.byKey(const ValueKey('kakuro-redo')));
      expect(cellText(first, '$wrong'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(dailyId)!['hints'], 1);
      await tearDownScreen(tester);
    });
  });

  testWidgets('notes mode pencils digits and the physical keyboard works', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, daily);
      expect(find.text('Notes off'), findsOneWidget);
      await tapThenPump(tester, cell(first));
      await tapThenPump(tester, find.byKey(const ValueKey('kakuro-notes')));
      expect(find.text('Notes on'), findsOneWidget);
      await tapThenPump(tester, key(wrong));
      expect(cellText(first, '$wrong'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(find.text('Notes off'), findsOneWidget);
      await tester.sendKeyEvent(_digitKey(answer));
      await tester.pump();
      expect(cellText(first, '$answer'), findsOneWidget);
      expect(cellText(first, '$wrong'), findsNothing, reason: 'a value clears the notes');

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(cellText(first, '$answer'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(_digitKey(answer));
      await tester.pump();
      expect(cellText(first, '$answer'), findsOneWidget, reason: 'arrows move the selection and back');

      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(cellText(first, '$answer'), findsNothing, reason: 'Z undoes');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.pump();
      expect(cellText(first, '$answer'), findsOneWidget, reason: 'Y redoes');
      await tearDownScreen(tester);
    });
  });

  testWidgets('the timer counts while playing and is shown only when enabled', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, daily);
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
        GameResult(puzzleId: smallId, completedAt: DateTime.utc(2026, 9, 11), solved: true, seconds: 300, hints: 1),
      );
      await pumpScreen(tester, small);
      expect(find.text('See result'), findsOneWidget);
      expect(key(1), findsNothing);
      expect(find.byKey(const ValueKey('kakuro-check')), findsNothing);
      for (final w in smallPuzzle.whiteCells) {
        expect(cellText(w, '${smallPuzzle.solution[w]}'), findsOneWidget);
      }
      expect(find.text('✓3'), findsNWidgets(2));
      expect(find.text('✓4'), findsNWidgets(2));
      await tester.tap(cell(4));
      await tester.pump();
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Solved'), findsWidgets);
      await tearDownScreen(tester);
    });
  });

  testWidgets('filling the last cell completes the puzzle once with a share line', (tester) async {
    await tester.runAsync(() async {
      var state = KakuroState.initial(smallPuzzle);
      for (final w in smallPuzzle.whiteCells) {
        if (w != 8) state = state.select(w).setValue(smallPuzzle.solution[w]);
      }
      await store.saveProgress(smallId, state.select(8).revealCell().undo().tick(42).toJson());
      await pumpScreen(tester, small, isArchivePlay: true);
      expect(find.text('1 hint'), findsOneWidget);
      expect(find.text('✓3'), findsOneWidget, reason: 'the finished across run shows a tick');
      await tapThenPump(tester, cell(8));
      await tapThenPump(tester, key(smallPuzzle.solution[8]));
      await pumpUntil(tester, () => store.result(smallId) != null && !store.hasProgress(smallId), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Solved').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      expect(find.text('Solved in 0:42 · 1 hint'), findsOneWidget);
      final result = store.result(smallId)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 42);
      expect(result.hints, 1);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['➕ 0:42 · 1 hint']);
      expect(store.hasProgress(smallId), isFalse);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a full board that breaks a rule is not completed and shows the run marks', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, small);
      await tapThenPump(tester, cell(4));
      await tapThenPump(tester, key(2));
      await tapThenPump(tester, cell(5));
      await tapThenPump(tester, key(1));
      expect(find.text('✓3'), findsOneWidget, reason: '2 + 1 meets the across clue');
      await tapThenPump(tester, cell(7));
      await tapThenPump(tester, key(2));
      expect(find.text('!4'), findsOneWidget, reason: '2 + 2 repeats');
      expect(find.descendant(of: cell(4), matching: find.text('!')), findsOneWidget);
      await tapThenPump(tester, cell(8));
      await tapThenPump(tester, key(2));
      expect(find.text('Every cell is filled, but something is not right yet.'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.result(smallId), isNull);
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
