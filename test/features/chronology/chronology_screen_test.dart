import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/chronology/chronology.dart';
import 'package:playthepaper/features/games/chronology/chronology_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../engines/chronology/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('chronology-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: flightPayload(),
    reveal: flightReveal(),
    sources: [
      for (final s in flightItem()['sources'] as List) SourceRef.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
  final puzzle = ChronologyPuzzle.parse(record.payload, record.reveal);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_chronology');
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
          home: ChronologyScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder card(String id) => find.byKey(ValueKey('chronology-card-$id'));

  List<String> shownOrder(WidgetTester tester) {
    final cards = [for (final id in puzzle.eventIds) (id, tester.getTopLeft(card(id)).dy)]..sort((a, b) => a.$2.compareTo(b.$2));
    return cards.map((c) => c.$1).toList();
  }

  Future<void> tapThenSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the shuffled cards and the arrow buttons move them and save progress', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(shownOrder(tester), ['b', 'd', 'a', 'c']);
      expect(find.text('Milestones of flight'), findsOneWidget);
      expect(find.text('1903'), findsNothing, reason: 'years stay hidden during play');
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('chronology-up-0'))).onPressed, isNull);

      await tapThenSettle(tester, find.byKey(const ValueKey('chronology-up-2')));
      expect(shownOrder(tester), ['b', 'a', 'd', 'c']);
      await tapThenSettle(tester, find.byKey(const ValueKey('chronology-up-1')));
      expect(shownOrder(tester), ['a', 'b', 'd', 'c']);
      await pumpUntil(tester, () => store.progress(id)?['order']?.join() == 'abdc', reason: 'progress saved');

      await tapThenSettle(tester, find.byKey(const ValueKey('chronology-undo')));
      expect(shownOrder(tester), ['b', 'a', 'd', 'c']);
      await pumpUntil(tester, () => store.progress(id)?['order']?.join() == 'badc', reason: 'undo saved');
      await tearDownScreen(tester);
    });
  });

  testWidgets('tapping a card picks it up and tapping another moves it there', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenSettle(tester, card('a'));
      expect(find.text('Picked up'), findsOneWidget);
      await tapThenSettle(tester, card('b'));
      expect(find.text('Picked up'), findsNothing);
      expect(shownOrder(tester), ['a', 'b', 'd', 'c']);
      await tearDownScreen(tester);
    });
  });

  testWidgets('the keyboard moves the cursor, picks a card up and carries it', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Picked up'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(shownOrder(tester), ['b', 'a', 'd', 'c']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(shownOrder(tester), ['a', 'b', 'd', 'c']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Picked up'), findsNothing);
      await pumpUntil(tester, () => store.progress(id)?['order']?.join() == 'abdc', reason: 'progress saved');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a hint locks the earliest misplaced event in place and is counted', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tapThenSettle(tester, find.byKey(const ValueKey('chronology-hint')));
      await tapThenSettle(tester, find.text('Place'));
      expect(shownOrder(tester), ['a', 'b', 'd', 'c']);
      expect(find.text('Placed by a hint'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id)?['hints'] == 1, reason: 'hint saved');
      expect(store.progress(id)!['locked'], 1);
      await tearDownScreen(tester);
    });
  });

  testWidgets('submitting scores the order, saves the result once and shows the years', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, ChronologyState.initial(puzzle).move(2, 0).toJson());
      await pumpScreen(tester, isArchivePlay: true);
      expect(shownOrder(tester), ['a', 'b', 'd', 'c']);
      await tapThenSettle(tester, find.byKey(const ValueKey('chronology-submit')));
      await tapThenSettle(tester, find.text('Submit').last);
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Not this time').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.points, 2);
      expect(result.maxPoints, 4);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['🕰 2/4', '🟩🟩🟥🟥']);
      expect(find.text('2/4'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('1903'), findsOneWidget);
      expect(find.text('1969'), findsOneWidget);
      expect(find.text('You had this here'), findsNWidgets(2));
      expect(find.text('You had this 4th'), findsOneWidget);
      expect(find.text('You had this 3rd'), findsOneWidget);
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('chronology-submit')), findsNothing);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with the verified order and See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(puzzleId: id, completedAt: DateTime.utc(2026, 9, 10), solved: true, points: 4, maxPoints: 4, hints: 0),
      );
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('chronology-submit')), findsNothing);
      expect(find.byKey(const ValueKey('chronology-up-0')), findsNothing);
      expect(find.text('1927'), findsOneWidget);
      expect(find.text('The verified order, earliest first.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SOURCES'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Powered flight began'), findsOneWidget);
      expect(find.textContaining('17 December 1903'), findsOneWidget);
      await tapThenSettle(tester, find.text('See result'));
      expect(find.text('Story found'), findsOneWidget);
      expect(find.text('The order'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
