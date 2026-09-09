import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/merge/merge.dart';
import 'package:playthepaper/features/games/merge/merge_extras.dart';
import 'package:playthepaper/features/games/merge/merge_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves after each
/// slide to Hive, and that file I/O can only finish with a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('merge-2026-09-10-en-v1');
  final puzzle = MergePuzzle(seed: 12345);
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: puzzle.toPayload(),
    reveal: puzzle.toReveal(),
  );

  /// One slide from stuck: sliding left packs the last row and the only free
  /// square then sits between two 16s, so the new tile cannot merge either way.
  MergeState almostStuck() => MergeState.fromJson({
        'seed': puzzle.seed,
        'size': 4,
        'tiles': [
          2, 4, 2, 4, //
          4, 2, 4, 2, //
          2, 4, 8, 16, //
          0, 4, 2, 16, //
        ],
        'score': 5000,
        'moves': 40,
        'random': 1234,
      });

  /// A free game with room to move, so the arrows and New game both bite.
  MergeState freeGame() => MergeState.fromJson({
        'seed': 777,
        'size': 4,
        'tiles': [
          2, 4, 0, 0, //
          0, 0, 0, 0, //
          0, 0, 0, 0, //
          0, 0, 0, 0, //
        ],
        'score': 5000,
        'moves': 12,
        'random': 4321,
      });

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_merge');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Everything is checked at the size of a small phone, so an overflow in
  /// the board or the controls fails the test.
  Future<void> pumpScreen(WidgetTester tester, {bool isArchivePlay = false}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: MergeScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
        ),
      ),
    );
    await settle(tester);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
    }
    expect(find.byType(BottomSheet), findsNothing, reason: 'the first-run help sheet must be dismissed');
  }

  Future<void> tearDownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Finder arrow(MergeDirection d) => find.byKey(ValueKey('merge-move-${d.slug}'));
  Finder cell(int index) => find.byKey(ValueKey('merge-cell-$index'));

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the arrows and the keyboard slide the board, and every slide is saved', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 16; i++) {
        expect(cell(i), findsOneWidget, reason: 'cell $i');
      }
      for (final d in MergeDirection.values) {
        expect(arrow(d), findsOneWidget, reason: d.slug);
      }
      expect(find.text('BEST DAILY'), findsOneWidget);
      expect(store.hasProgress(id), isFalse);

      await tapThenPump(tester, arrow(MergeDirection.left));
      await pumpUntil(tester, () => store.hasProgress(id), reason: 'the first slide is saved');
      final first = MergeState.fromJson(store.progress(id)!);
      expect(first.moves, 1);
      expect(first.tiles[8], 4, reason: 'the 4 slid to the left edge');
      expect(first.tiles.where((v) => v != 0).length, 3, reason: 'one new tile');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await pumpUntil(tester, () => MergeState.fromJson(store.progress(id)!).moves == 2, reason: 'the second slide');
      final second = MergeState.fromJson(store.progress(id)!);
      expect(second.tiles[0], isNot(0), reason: 'the column packed to the top');
      expect(store.result(id), isNull, reason: 'the game is not over');

      await tapThenPump(tester, find.byKey(const ValueKey('merge-undo')));
      await pumpUntil(tester, () => MergeState.fromJson(store.progress(id)!).moves == 1, reason: 'one slide back');
      final undone = MergeState.fromJson(store.progress(id)!);
      expect(undone.tiles, first.tiles);
      expect(undone.undosUsed, 1, reason: 'an undo counts as a hint');
      expect(find.text('Undo (1)'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a slide that fills the last square ends the day and records the score', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, almostStuck().toJson());
      await pumpScreen(tester, isArchivePlay: true);
      expect(find.text('5,000'), findsOneWidget, reason: 'the score carried over');

      await tapThenPump(tester, arrow(MergeDirection.left));
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Result').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isFalse, reason: '2048 was not reached');
      expect(result.points, 5000);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.note, 'Score 5,000 · best tile 16');
      expect(result.shareLines, ['🔢 5,000 · 16']);
      expect(store.hasProgress(id), isFalse, reason: 'progress gives way to the result');
      expect(MergeExtras.load(store).finishedState(id.toString()), isNotNull, reason: 'the board is kept to look at');
      await tearDownScreen(tester);
    });
  });

  testWidgets('Finish records the score as it stands', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, almostStuck().toJson());
      await pumpScreen(tester);
      await tapThenPump(tester, find.byKey(const ValueKey('merge-finish')));
      await tester.pumpAndSettle();
      expect(find.text('Finish today?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.points, 5000);
      expect(result.solved, isFalse);
      expect(result.note, 'Score 5,000 · best tile 16');
      await tearDownScreen(tester);
    });
  });

  testWidgets('reaching 2048 offers the choice to play on', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(
        id,
        MergeState.fromJson({
          'seed': puzzle.seed,
          'size': 4,
          'tiles': [
            1024, 1024, 0, 0, //
            0, 0, 0, 0, //
            0, 0, 0, 0, //
            0, 0, 0, 0, //
          ],
          'score': 20000,
          'moves': 300,
          'random': 55,
        }).toJson(),
      );
      await pumpScreen(tester);
      await tapThenPump(tester, arrow(MergeDirection.left));
      await pumpUntil(tester, () => find.text('2048 made').evaluate().isNotEmpty, reason: 'the choice is offered');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Keep going'));
      await tester.pumpAndSettle();
      expect(store.result(id), isNull, reason: 'playing on does not end the day');
      await pumpUntil(tester, () => MergeState.fromJson(store.progress(id)!).keepGoing, reason: 'the choice is saved');
      expect(find.text('2048 made. Playing on.'), findsOneWidget);

      await tapThenPump(tester, find.byKey(const ValueKey('merge-finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.points, 22048);
      expect(result.note, 'Score 22,048 · best tile 2048');
      expect(find.text('Reached 2048'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a finished day reopens read-only with See result', (tester) async {
    await tester.runAsync(() async {
      final finished = almostStuck().finish();
      await store.saveResult(GameResult(
        puzzleId: id,
        completedAt: DateTime.utc(2026, 9, 10),
        solved: false,
        points: 5000,
        hints: 1,
        note: 'Score 5,000 · best tile 16',
      ));
      await const MergeExtras().withFinished(id.toString(), finished).save(store);
      await pumpScreen(tester);

      expect(find.text('See result'), findsOneWidget);
      expect(arrow(MergeDirection.left), findsNothing, reason: 'a finished board takes no slides');
      expect(find.byKey(const ValueKey('merge-undo')), findsNothing);
      expect(find.descendant(of: cell(11), matching: find.text('16')), findsOneWidget);
      expect(find.text('Score 5,000 · best tile 16'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.descendant(of: cell(11), matching: find.text('16')), findsOneWidget, reason: 'keys do nothing');

      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('Your board'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('unlimited play is kept in extras and never becomes a result', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, almostStuck().toJson());
      await const MergeExtras().withUnlimited(freeGame()).save(store);
      await pumpScreen(tester);
      await tapThenPump(tester, find.text('Unlimited'));
      expect(find.text('BEST FREE'), findsOneWidget);
      expect(
        find.text('5,000'),
        findsNWidgets(2),
        reason: 'the free game was picked up where it was left, and it is the best so far',
      );
      expect(find.byKey(const ValueKey('merge-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('merge-finish')), findsNothing);

      for (final d in MergeDirection.values) {
        await tapThenPump(tester, arrow(d));
      }
      await pumpUntil(
        tester,
        () => (MergeExtras.load(store).unlimitedState()?.moves ?? 0) > 0,
        reason: 'the free game is saved in extras',
      );
      final free = MergeExtras.load(store).unlimitedState()!;
      expect(free.tiles.where((v) => v != 0).length, greaterThanOrEqualTo(2));
      expect(store.result(id), isNull, reason: 'free play is never recorded');
      expect(MergeState.fromJson(store.progress(id)!).moves, 40, reason: 'the daily is untouched');

      await tapThenPump(tester, find.byKey(const ValueKey('merge-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'New game'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () => MergeExtras.load(store).unlimitedState()!.moves == 0,
        reason: 'a new board is dealt',
      );
      expect(MergeExtras.load(store).bestUnlimited, free.score);
      await tearDownScreen(tester);
    });
  });
}
