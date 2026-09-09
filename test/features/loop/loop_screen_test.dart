import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/loop/loop.dart';
import 'package:playthepaper/features/games/loop/loop_board.dart';
import 'package:playthepaper/features/games/loop/loop_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../engines/loop/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each mark, and that file I/O can only complete with a real
/// event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('loop-2026-09-10-en-v1');
  final puzzle = LoopPuzzle.parse(smallPayload(clues: smallSparseClues), smallReveal());
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: smallPayload(clues: smallSparseClues),
    reveal: smallReveal(),
  );
  final grid = puzzle.grid;
  final last = grid.h(2, 2);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_loop');
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

  Future<void> pumpScreen(WidgetTester tester, {PuzzleRecord? puzzle, bool isArchivePlay = false}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: LoopScreen(play: PlayContext(store: store, record: puzzle ?? record, isArchivePlay: isArchivePlay)),
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

  Finder edge(int index) => find.byKey(ValueKey('loop-edge-$index'));
  Finder clue(int cell) => find.byKey(ValueKey('loop-clue-$cell'));
  String label(WidgetTester tester, Finder finder) => tester.getSemantics(finder).label;
  bool? selected(WidgetTester tester, int index) =>
      tester.getSemantics(edge(index)).flagsCollection.isSelected.toBoolOrNull();
  String marks(WidgetTester tester) => store.progress(id)!['marks'] as String;

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  /// Long press with the real clock: under [WidgetTester.runAsync] the
  /// recogniser's deadline is a real timer, so pumping alone never reaches it.
  Future<void> longPress(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('renders every edge and clue, and a tap draws a line that is saved', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      for (var e = 0; e < grid.edgeCount; e++) {
        expect(edge(e), findsOneWidget, reason: 'edge $e');
      }
      expect(label(tester, edge(grid.h(0, 0))), 'Top of row 1, column 1, empty');
      expect(label(tester, edge(grid.h(3, 2))), 'Bottom of row 3, column 3, empty');
      expect(label(tester, edge(grid.v(0, 0))), 'Left of row 1, column 1, empty');
      expect(label(tester, edge(grid.v(0, 3))), 'Right of row 1, column 3, empty');
      expect(label(tester, clue(grid.cell(1, 0))), 'Row 2, column 1, clue 2, 0 lines');
      expect(label(tester, clue(grid.cell(2, 0))), 'Row 3, column 1, clue 0, 0 lines, met');
      expect(find.text('1 of 3 numbers met'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);

      await tapThenPump(tester, edge(grid.h(0, 0)));
      expect(label(tester, edge(grid.h(0, 0))), 'Top of row 1, column 1, line');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(marks(tester)[grid.h(0, 0)], '-');

      await tapThenPump(tester, edge(grid.h(2, 0)));
      expect(label(tester, clue(grid.cell(2, 0))), 'Row 3, column 1, clue 0, 1 line, too many');
      expect(find.text('✕'), findsOneWidget);
      expect(find.text('A number can no longer come out right.'), findsOneWidget);

      await tapThenPump(tester, edge(grid.h(2, 0)));
      expect(label(tester, clue(grid.cell(2, 0))), 'Row 3, column 1, clue 0, 0 lines, met');
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('the Crosses button and a long press mark a cross, and undo steps back', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.text('Lines'), findsOneWidget);
      await tapThenPump(tester, find.byKey(const ValueKey('loop-mode')));
      expect(find.text('Crosses'), findsOneWidget);

      await tapThenPump(tester, edge(grid.h(0, 2)));
      expect(label(tester, edge(grid.h(0, 2))), 'Top of row 1, column 3, crossed off');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(marks(tester)[grid.h(0, 2)], 'x');

      await tapThenPump(tester, find.byKey(const ValueKey('loop-undo')));
      expect(label(tester, edge(grid.h(0, 2))), 'Top of row 1, column 3, empty');
      await tapThenPump(tester, find.byKey(const ValueKey('loop-redo')));
      expect(label(tester, edge(grid.h(0, 2))), 'Top of row 1, column 3, crossed off');

      await tapThenPump(tester, find.byKey(const ValueKey('loop-mode')));
      expect(find.text('Lines'), findsOneWidget);
      await longPress(tester, edge(grid.h(1, 1)));
      expect(label(tester, edge(grid.h(1, 1))), 'Top of row 2, column 2, crossed off');
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('the arrows move a cursor over the edges, Enter draws and X crosses', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await tapThenPump(tester, edge(grid.h(0, 1)));
      expect(selected(tester, grid.h(0, 1)), isTrue, reason: 'a tap puts the cursor on that edge');

      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(selected(tester, grid.h(0, 0)), isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      expect(label(tester, edge(grid.h(0, 0))), 'Top of row 1, column 1, line');

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(selected(tester, grid.v(0, 0)), isTrue, reason: 'down steps onto the row of down edges');
      await key(tester, LogicalKeyboardKey.keyX);
      expect(label(tester, edge(grid.v(0, 0))), 'Left of row 1, column 1, crossed off');

      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(selected(tester, grid.v(0, 1)), isTrue);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(selected(tester, grid.h(0, 0)), isTrue);
      await key(tester, LogicalKeyboardKey.space);
      expect(label(tester, edge(grid.h(0, 0))), 'Top of row 1, column 1, empty');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(marks(tester)[grid.v(0, 0)], 'x');
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('the daily board fits a 390-pixel phone and a tap takes the nearest edge', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final daily = LoopGenerator().generate(DateTime.utc(2026, 9, 10));
      await pumpScreen(tester, puzzle: daily);
      final board = LoopPuzzle.parse(daily.payload, daily.reveal);
      expect(board.width, 6);
      expect(board.height, 6);
      for (var e = 0; e < board.grid.edgeCount; e++) {
        expect(edge(e), findsOneWidget, reason: 'edge $e');
      }
      expect(tester.getSize(find.byType(LoopBoard)).width, lessThanOrEqualTo(390));
      final step = tester.getCenter(edge(board.grid.h(0, 1))).dx - tester.getCenter(edge(board.grid.h(0, 0))).dx;
      expect(step, greaterThanOrEqualTo(44), reason: 'each edge owns a band at least 44dp across');
      for (final control in ['mode', 'undo', 'redo', 'hint']) {
        final size = tester.getSize(find.byKey(ValueKey('loop-$control')));
        expect(size.height, greaterThanOrEqualTo(44), reason: control);
        expect(size.width, greaterThanOrEqualTo(44), reason: control);
      }

      final away = tester.getCenter(edge(board.grid.h(0, 0))) + Offset(0, step * 0.3);
      await tester.tapAt(away);
      await tester.pump();
      expect(label(tester, edge(board.grid.h(0, 0))), endsWith('line'), reason: 'a near miss still draws the edge');
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('a hint fills one edge and is counted', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, find.byKey(const ValueKey('loop-hint')));
      await tester.pumpAndSettle();
      await tapThenPump(tester, find.text('Fill in'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['hints'], 1);
      expect(marks(tester).replaceAll('.', ''), hasLength(1));
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
      final semantics = tester.ensureSemantics();
      await store.saveResult(
        GameResult(puzzleId: id, completedAt: DateTime.utc(2026, 9, 10), solved: true, seconds: 300, hints: 1),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.text('Solved in 5:00 · 1 hint'), findsOneWidget);
      expect(find.byKey(const ValueKey('loop-undo')), findsNothing);
      expect(find.byKey(const ValueKey('loop-hint')), findsNothing);
      expect(label(tester, edge(grid.h(0, 0))), 'Top of row 1, column 1, line');
      expect(tester.getSemantics(edge(grid.h(0, 0))).flagsCollection.isButton, isFalse);

      await tapThenPump(tester, edge(grid.h(0, 2)));
      expect(label(tester, edge(grid.h(0, 2))), 'Top of row 1, column 3, empty', reason: 'taps do nothing');
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Solved'), findsOneWidget);
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('drawing the last line completes the puzzle once with a spoiler-free share line', (tester) async {
    await tester.runAsync(() async {
      var state = LoopState.initial(puzzle);
      for (var e = 0; e < grid.edgeCount; e++) {
        if (puzzle.solution[e] && e != last) state = state.toggleLine(e);
      }
      await store.saveProgress(id, state.tick(42).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      await tapThenPump(tester, edge(last));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Solved').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 42);
      expect(result.hints, 0);
      expect(result.shareLines, ['⭕ 0:42']);
      expect(result.isArchivePlay, isTrue);
      expect(store.hasProgress(id), isFalse);
      await tearDownScreen(tester);
    });
  });
}
