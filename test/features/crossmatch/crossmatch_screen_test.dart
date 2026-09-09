import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/crossmatch/crossmatch.dart';
import 'package:playthepaper/features/games/crossmatch/crossmatch_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../engines/crossmatch/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('crossmatch-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: placesPayload(),
    reveal: placesReveal(),
    sources: [
      for (final s in placesItem()['sources'] as List) SourceRef.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
  final puzzle = CrossmatchPuzzle.parse(record.payload, record.reveal);
  int tile(String name) => puzzle.tiles.indexOf(name);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_crossmatch');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester, {bool isArchivePlay = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: CrossmatchScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
    }
    expect(find.byType(BottomSheet), findsNothing, reason: 'the first-run help sheet must be dismissed');
  }

  Future<void> tearDownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> tapThenSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder trayTile(String name) => find.byKey(ValueKey('crossmatch-tile-${tile(name)}'));
  Finder cell(int index) => find.byKey(ValueKey('crossmatch-cell-$index'));
  List<int>? placement() => (store.progress(id)?['placement'] as List?)?.cast<int>();

  CrossmatchState solvedState() {
    var state = CrossmatchState.initial(puzzle);
    for (var c = 0; c < CrossmatchPuzzle.cellCount; c++) {
      state = state.place(puzzle.tileAt(c), c);
    }
    return state;
  }

  testWidgets('shows the grid and the tray, and a tile then a cell places it and saves progress', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('Islands and volcanoes'), findsOneWidget);
      expect(find.text('In Iceland'), findsOneWidget);
      expect(find.text('Volcano'), findsOneWidget);
      expect(trayTile('Naples'), findsOneWidget);
      expect(find.text('Put each tile where it meets both conditions.'), findsOneWidget);

      await tapThenSettle(tester, trayTile('Naples'));
      await tapThenSettle(tester, cell(0));
      await pumpUntil(tester, () => placement()?[0] == tile('Naples'), reason: 'placement saved');
      expect(trayTile('Naples'), findsNothing, reason: 'the tile has left the tray');

      await tapThenSettle(tester, cell(0));
      await pumpUntil(tester, () => placement()?[0] == -1, reason: 'the tile went back to the tray');
      expect(trayTile('Naples'), findsOneWidget);

      await tapThenSettle(tester, cell(4));
      await pumpUntil(tester, () => placement()?[4] == tile('Naples'), reason: 'the picked tile moved on');
      await tapThenSettle(tester, find.byKey(const ValueKey('crossmatch-undo')));
      await pumpUntil(tester, () => placement()?[4] == -1, reason: 'undo saved');
      await tearDownScreen(tester);
    });
  });

  testWidgets('holding a tile and dragging it onto a cell places it', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      final gesture = await tester.startGesture(tester.getCenter(trayTile('Sicily')));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(cell(3)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => placement()?[3] == tile('Sicily'), reason: 'the dragged tile landed');
      await tearDownScreen(tester);
    });
  });

  testWidgets('the keyboard moves between the grid and the tray and places a tile', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      final hekla = tile('Hekla');
      await pumpUntil(tester, () => placement()?[7] == hekla, reason: 'the keyboard placed the first tile');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => placement()?[7] == -1, reason: 'backspace empties the cell');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a check marks the tiles that are out of place and counts a hint', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, CrossmatchState.initial(puzzle).place(tile('Hekla'), 0).toJson());
      await pumpScreen(tester);
      expect(find.text('Check 3'), findsOneWidget);
      await tapThenSettle(tester, find.byKey(const ValueKey('crossmatch-check')));
      await tapThenSettle(tester, find.text('Check').last);
      expect(find.text('Not here'), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id)?['checks'] == 1, reason: 'the check is counted');
      expect(find.text('Check 2'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('submitting scores the grid, saves one result and shows the verified answers', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, solvedState().place(puzzle.tileAt(0), 1).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      await tapThenSettle(tester, find.byKey(const ValueKey('crossmatch-submit')));
      await tapThenSettle(tester, find.text('Submit').last);
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Not this time').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.points, 7);
      expect(result.maxPoints, 9);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['🧩 7/9', '⬜🟥🟩', '🟩🟩🟩', '🟩🟩🟩']);
      expect(find.text('7/9'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('The verified grid, with a line on every answer.'), findsOneWidget);
      expect(find.byKey(const ValueKey('crossmatch-submit')), findsNothing);
      expect(find.text('See result'), findsOneWidget);
      final reveal = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('You left this cell empty'), 120, scrollable: reveal);
      await tester.scrollUntilVisible(find.text('You had Naples'), 120, scrollable: reveal);
      await tester.scrollUntilVisible(find.text('A port city in the Kansai region of Japan.'), 120, scrollable: reveal);
      expect(find.text('You had this right'), findsWidgets);
      await tester.scrollUntilVisible(find.text('SOURCES'), 200, scrollable: reveal);
      expect(find.textContaining('Naples is the regional capital'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with the verified grid and See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(puzzleId: id, completedAt: DateTime.utc(2026, 9, 10), solved: true, points: 9, maxPoints: 9, hints: 1),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('crossmatch-submit')), findsNothing);
      expect(find.byKey(const ValueKey('crossmatch-check')), findsNothing);
      expect(trayTile('Naples'), findsNothing);
      expect(find.text('Naples'), findsWidgets, reason: 'the verified grid names every tile');
      await tester.scrollUntilVisible(find.text('SOURCES'), 200, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(
        find.textContaining('Hekla is an active stratovolcano'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapThenSettle(tester, find.text('See result'));
      expect(find.text('Story found'), findsOneWidget);
      expect(find.text('The grid'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
