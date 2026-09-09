import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:playthepaper/features/games/bridges/bridges_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../engines/bridges/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O can only complete with a real
/// event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('bridges-2026-09-10-en-v1');
  PuzzleRecord record(Map<String, dynamic> payload, Map<String, dynamic> reveal) => PuzzleRecord(
        id: id,
        locale: 'en-GB',
        contentVersion: 1,
        scoringVersion: 1,
        payload: payload,
        reveal: reveal,
      );
  final ring = record(ringPayload, ringReveal);
  final crossing = record(crossingPayload, crossingReveal);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_bridges');
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
          home: BridgesScreen(play: PlayContext(store: store, record: puzzle ?? ring, isArchivePlay: isArchivePlay)),
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

  Finder island(int index) => find.byKey(ValueKey('bridges-island-$index'));
  String label(WidgetTester tester, int index) => tester.getSemantics(island(index)).label;
  bool isSelected(WidgetTester tester, int index) =>
      tester.getSemantics(island(index)).flagsCollection.isSelected.toBoolOrNull() ?? false;
  bool isButton(WidgetTester tester, int index) => tester.getSemantics(island(index)).flagsCollection.isButton;

  Future<void> tapThenPump(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  testWidgets('renders every island and draws, doubles and undoes a bridge between two taps', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      for (var i = 0; i < 4; i++) {
        expect(island(i), findsOneWidget, reason: 'island $i');
        expect(tester.getSize(island(i)).shortestSide, greaterThanOrEqualTo(44));
      }
      expect(label(tester, 0), 'Island row 1, column 1, needs 2, has 0');
      expect(find.text('0 of 4 islands complete'), findsOneWidget);

      await tapThenPump(tester, island(0));
      expect(isSelected(tester, 0), isTrue);
      expect(label(tester, 1), endsWith('in line with the selected island'));
      expect(label(tester, 3), isNot(contains('in line')));
      await tapThenPump(tester, island(1));
      expect(label(tester, 0), 'Island row 1, column 1, needs 2, has 1: 1 right');
      expect(label(tester, 1), 'Island row 1, column 3, needs 2, has 1: 1 left, in line with the selected island');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['bridges'], [1, 0, 0, 0]);

      await tapThenPump(tester, island(1));
      expect(label(tester, 0), contains('has 2: 2 right, complete'));
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(find.text('2 of 4 islands complete'), findsOneWidget);

      await tapThenPump(tester, island(2));
      expect(label(tester, 0), contains('has 3: 2 right, 1 down, too many'));
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('An island has more bridges than its number.'), findsOneWidget);

      await tapThenPump(tester, find.byKey(const ValueKey('bridges-undo')));
      expect(label(tester, 0), contains('has 2: 2 right, complete'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['bridges'], [2, 0, 0, 0]);
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('a bridge that would cross another is refused with a notice', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, puzzle: crossing);
      await tapThenPump(tester, island(1));
      await tapThenPump(tester, island(4));
      expect(label(tester, 1), contains('has 1: 1 down'));
      await tapThenPump(tester, island(2));
      expect(isSelected(tester, 2), isTrue, reason: 'an island out of line becomes the selection');
      await tapThenPump(tester, island(3));
      expect(label(tester, 3), contains('has 0'));
      expect(find.text('Bridges cannot cross.'), findsOneWidget);
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('the physical keyboard moves a cursor, connects with Enter and sets counts with digits', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.enter);
      expect(isSelected(tester, 0), isTrue, reason: 'the cursor starts on the first island');
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.space);
      expect(label(tester, 0), contains('has 1: 1 right'));
      await key(tester, LogicalKeyboardKey.digit2);
      expect(label(tester, 0), contains('has 2: 2 right'));
      await key(tester, LogicalKeyboardKey.digit0);
      expect(label(tester, 0), contains('has 0'));
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await key(tester, LogicalKeyboardKey.digit1);
      expect(label(tester, 0), contains('has 1: 1 down'));
      await key(tester, LogicalKeyboardKey.escape);
      expect(isSelected(tester, 0), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['bridges'], [0, 1, 0, 0]);
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('the daily board fits a 390-pixel phone with tap targets of at least 44dp', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final daily = BridgesGenerator().generate(DateTime.utc(2026, 9, 10));
      await pumpScreen(tester, puzzle: daily);
      final puzzle = BridgesPuzzle.parse(daily.payload, daily.reveal);
      expect(puzzle.layout.width, 7);
      for (var i = 0; i < puzzle.islandCount; i++) {
        expect(island(i), findsOneWidget, reason: 'island $i');
        expect(tester.getSize(island(i)).shortestSide, greaterThanOrEqualTo(44), reason: 'island $i');
      }
      for (final id in ['undo', 'hint']) {
        expect(tester.getSize(find.byKey(ValueKey('bridges-$id'))).height, greaterThanOrEqualTo(44));
      }
      semantics.dispose();
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

  testWidgets('a hint draws a certain bridge and is counted', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await tapThenPump(tester, find.byKey(const ValueKey('bridges-hint')));
      await tester.pumpAndSettle();
      await tapThenPump(tester, find.text('Draw'));
      await tester.pumpAndSettle();
      expect(label(tester, 0), contains('has 1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.progress(id)!['hints'], 1);
      semantics.dispose();
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
      expect(find.byKey(const ValueKey('bridges-undo')), findsNothing);
      expect(find.byKey(const ValueKey('bridges-hint')), findsNothing);
      expect(find.text('Solved in 5:00 · 1 hint'), findsOneWidget);
      expect(label(tester, 0), 'Island row 1, column 1, needs 2, has 2: 1 right, 1 down, complete');
      expect(isButton(tester, 0), isFalse);
      await tester.tap(island(1));
      await tester.pump();
      expect(label(tester, 0), contains('complete'), reason: 'taps do nothing on a finished board');
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Solved'), findsOneWidget);
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('drawing the last bridge completes the puzzle once with a spoiler-free share line', (tester) async {
    await tester.runAsync(() async {
      final puzzle = BridgesPuzzle.parse(ringPayload, ringReveal);
      final state = BridgesState.initial(puzzle).setBridges(0, 1).setBridges(1, 1).setBridges(2, 1).tick(42);
      await store.saveProgress(id, state.toJson());
      await pumpScreen(tester, isArchivePlay: true);
      expect(find.text('2 of 4 islands complete'), findsOneWidget);
      await tapThenPump(tester, island(2));
      await tapThenPump(tester, island(3));
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Solved').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.seconds, 42);
      expect(result.hints, 0);
      expect(result.shareLines, ['🌉 0:42']);
      expect(result.isArchivePlay, isTrue);
      expect(store.hasProgress(id), isFalse);
      await tearDownScreen(tester);
    });
  });
}
