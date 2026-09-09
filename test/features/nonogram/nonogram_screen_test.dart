import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/nonogram/nonogram.dart';
import 'package:playthepaper/features/games/nonogram/nonogram_screen.dart';
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
  final id = PuzzleId.parse('nonogram-2026-09-11-en-v1');

  /// A 5×5 cross: rows 3, 1, 5, 1, 3.
  final puzzle = NonogramPuzzle.fromPicture(
    picture: const ['01110', '00100', '11111', '00100', '01110'],
    title: 'Cross',
  );
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: puzzle.toPayload(),
    reveal: puzzle.toReveal(),
  );
  final filled = [for (var i = 0; i < 25; i++) if (puzzle.isFilled(i)) i];

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_nonogram');
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
          home: NonogramScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder cell(int index) => find.byKey(ValueKey('nonogram-cell-$index'));
  Finder button(String id) => find.byKey(ValueKey('nonogram-$id'));

  String marks() => store.progress(id)?['cells'] as String? ?? '';

  String labelOf(WidgetTester tester, int index) =>
      tester.widget<Semantics>(cell(index)).properties.label ?? '';

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> confirm(WidgetTester tester, String action) async {
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, action));
    await settle(tester);
  }

  testWidgets('renders every cell and clue, and a tap steps a cell on', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 25; i++) {
        expect(cell(i), findsOneWidget, reason: 'cell $i');
      }
      expect(find.byKey(const ValueKey('nonogram-row-clue-2')), findsOneWidget);
      expect(labelOf(tester, 0), 'Row 1, column 1, blank');

      await tapThenPump(tester, cell(0));
      expect(labelOf(tester, 0), 'Row 1, column 1, filled');
      await pumpUntil(tester, () => store.hasProgress(id), reason: 'progress saved after a tap');
      expect(marks()[0], '#');

      await tapThenPump(tester, cell(0));
      expect(labelOf(tester, 0), 'Row 1, column 1, crossed');
      await tapThenPump(tester, cell(0));
      expect(labelOf(tester, 0), 'Row 1, column 1, blank');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a drag paints a run that undoes as one step', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      final gesture = await tester.startGesture(tester.getCenter(cell(10)));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(tester.getCenter(cell(11)));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(cell(13)));
      await tester.pump();
      await gesture.up();
      await settle(tester);

      for (final i in [10, 11, 12, 13]) {
        expect(labelOf(tester, i), contains('filled'), reason: 'cell $i');
      }
      expect(labelOf(tester, 14), contains('blank'));

      await tapThenPump(tester, button('undo'));
      for (final i in [10, 11, 12, 13]) {
        expect(labelOf(tester, i), contains('blank'), reason: 'cell $i after undo');
      }
      await tearDownScreen(tester);
    });
  });

  testWidgets('the keyboard moves a cursor, fills and crosses', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(labelOf(tester, 1), contains('filled'));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump();
      expect(labelOf(tester, 6), contains('crossed'));

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(labelOf(tester, 6), contains('blank'));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(labelOf(tester, 5), contains('filled'), reason: 'Enter steps the cell under the cursor on');
      await tearDownScreen(tester);
    });
  });

  testWidgets('checking a row marks its wrong cells and counts a hint', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(0));
      expect(labelOf(tester, 0), contains('filled'));

      await tester.tap(button('check'));
      await confirm(tester, 'Check');
      expect(labelOf(tester, 0), contains('marked wrong'));
      await pumpUntil(tester, () => store.progress(id)?['hints'] == 1, reason: 'the hint is counted');
      expect(store.progress(id)!['flagged'], [0]);
      await tearDownScreen(tester);
    });
  });

  testWidgets('reset clears the grid after a confirmation', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, cell(0));
      await tapThenPump(tester, cell(1));
      await tester.tap(button('reset'));
      await confirm(tester, 'Clear');
      expect(labelOf(tester, 0), contains('blank'));
      expect(labelOf(tester, 1), contains('blank'));
      await pumpUntil(tester, () => marks().isNotEmpty && !marks().contains('#'), reason: 'the cleared grid is saved');
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

  testWidgets('filling the last cell completes the puzzle once and saves a spoiler-free share line', (tester) async {
    await tester.runAsync(() async {
      var state = NonogramState.initial(puzzle);
      for (final i in filled.take(filled.length - 1)) {
        state = state.set(i, CellMark.filled);
      }
      await store.saveProgress(id, state.tick(83).checkRow(4).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      expect(find.text('Rows 4/5 · Columns 4/5'), findsOneWidget);

      await tapThenPump(tester, cell(filled.last));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('The picture').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 83);
      expect(result.hints, 1);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['🖼 5×5 in 1:23']);
      expect(result.shareLines.single, isNot(contains('🟩')), reason: 'the thumbnail would be a spoiler');
      expect(find.text('Solved'), findsOneWidget);
      expect(find.text('Cross'), findsWidgets, reason: 'the reveal names the picture');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with the picture and a See result button', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 11),
          solved: true,
          seconds: 120,
          hints: 0,
          shareLines: const ['🖼 5×5 in 2:00'],
        ),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.text('Cross'), findsOneWidget);
      expect(button('undo'), findsNothing);
      expect(button('check'), findsNothing);
      expect(labelOf(tester, 1), contains('filled'), reason: 'the picture is shown, not the empty grid');
      expect(labelOf(tester, 0), contains('blank'));

      await tapThenPump(tester, cell(1));
      expect(labelOf(tester, 1), contains('filled'), reason: 'a finished board does not take taps');
      expect(store.hasProgress(id), isFalse);

      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('The picture'), findsOneWidget);
      expect(find.text('Solved in 2:00'), findsWidgets);
      await tearDownScreen(tester);
    });
  });
}
