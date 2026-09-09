import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/features/games/target/target_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// A small fixture so a step or two reaches the target: 50 × 3 is 150.
/// Every body runs under [WidgetTester.runAsync] because the screen saves
/// progress to Hive after each step, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('target-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: const {
      'tiles': [25, 50, 3, 4, 2, 1],
      'target': 150,
    },
    reveal: const {'expression': '50 * 3'},
  );

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_target');
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

  Future<void> pumpScreen(WidgetTester tester, {bool isArchivePlay = false}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          home: TargetScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder tile(int tileId) => find.byKey(ValueKey('target-tile-$tileId'));
  Finder op(String name) => find.byKey(ValueKey('target-op-$name'));

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  testWidgets('a tile, an operation and a second tile make a step, and progress is saved', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('150'), findsOneWidget, reason: 'the target');
      for (final t in [0, 1, 2, 3, 4, 5]) {
        expect(tile(t), findsOneWidget, reason: 'tile $t');
      }
      expect(find.text('Pick a tile.'), findsOneWidget);

      await tapThenPump(tester, tile(0));
      expect(find.text('25 …'), findsOneWidget);
      await tapThenPump(tester, op('add'));
      expect(find.text('25 + …'), findsOneWidget);
      await tapThenPump(tester, tile(4));
      expect(find.text('25 + 2 = 27'), findsOneWidget);
      expect(tile(0), findsNothing, reason: 'the two tiles are consumed');
      expect(tile(4), findsNothing);
      expect(tile(6), findsOneWidget, reason: 'the answer becomes a new tile');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['steps'], [
        [0, '+', 4],
      ]);

      await tapThenPump(tester, find.byKey(const ValueKey('target-undo')));
      expect(find.text('25 + 2 = 27'), findsNothing);
      expect(tile(0), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['steps'], isEmpty);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a step that breaks a rule is refused with a reason', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, tile(2));
      await tapThenPump(tester, op('subtract'));
      await tapThenPump(tester, tile(3));
      expect(find.text('3 − 4 would go below one.'), findsOneWidget);
      expect(tile(2), findsOneWidget, reason: 'nothing was consumed');

      await tapThenPump(tester, op('divide'));
      await tapThenPump(tester, tile(3));
      expect(find.text('3 ÷ 4 does not come out exactly.'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('the physical keyboard picks tiles, operations and steps', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await key(tester, LogicalKeyboardKey.digit1);
      expect(find.text('25 …'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.numpadAdd);
      expect(find.text('25 + …'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Pick a tile.'), findsOneWidget);

      await key(tester, LogicalKeyboardKey.digit3);
      await key(tester, LogicalKeyboardKey.numpadMultiply);
      expect(find.text('3 × …'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.enter);
      expect(find.text('3 × 4 = 12'), findsOneWidget, reason: 'the arrows move the cursor and Enter picks');

      await key(tester, LogicalKeyboardKey.backspace);
      expect(find.text('3 × 4 = 12'), findsNothing);
      await tearDownScreen(tester);
    });
  });

  testWidgets('reaching the target completes the puzzle once and saves the result', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, isArchivePlay: true);
      await tapThenPump(tester, tile(1));
      await tapThenPump(tester, op('multiply'));
      await tapThenPump(tester, tile(2));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Reached 150').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.note, 'Reached 150');
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['🎯 150 exactly']);
      expect(store.hasProgress(id), isFalse);
      await tearDownScreen(tester);
    });
  });

  testWidgets('Show a solution ends play unsolved and reveals one route', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenPump(tester, tile(0));
      await tapThenPump(tester, op('multiply'));
      await tapThenPump(tester, tile(5));
      expect(find.text('25 × 1 = 25'), findsOneWidget);

      await tapThenPump(tester, find.byKey(const ValueKey('target-giveup')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show it'));
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.note, 'Closest 25 (125 off)');
      expect(result.hints, 1);
      expect(result.shareLines, ['🎯 125 off']);
      await tearDownScreen(tester);
    });
  });

  testWidgets('the board fits a 390-px-wide phone', (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpScreen(tester);
      for (final t in [0, 1, 2, 3, 4, 5]) {
        expect(tester.getSize(tile(t)).height, greaterThanOrEqualTo(44), reason: 'tile $t is tappable');
      }
      for (final name in ['add', 'subtract', 'multiply', 'divide']) {
        expect(tester.getSize(op(name)).height, greaterThanOrEqualTo(44), reason: '$name is tappable');
      }
      expect(tester.getSize(find.byKey(const ValueKey('target-undo'))).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with a See result button', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 10),
          solved: true,
          seconds: 120,
          hints: 0,
          note: 'Reached 150',
        ),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('target-undo')), findsNothing);
      expect(op('add'), findsNothing);
      expect(find.text('50 × 3'), findsOneWidget, reason: 'one way to the target is shown');

      await tapThenPump(tester, tile(1));
      expect(find.text('25 …'), findsNothing);
      expect(tile(1), findsOneWidget, reason: 'the finished board ignores taps');

      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Reached 150'), findsWidgets);
      await tearDownScreen(tester);
    });
  });
}
