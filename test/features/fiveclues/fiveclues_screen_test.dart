import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/fiveclues/fiveclues.dart';
import 'package:playthepaper/features/games/fiveclues/fiveclues_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../engines/fiveclues/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each guess, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('fiveclues-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: honeyPayload(),
    reveal: honeyReveal(),
    sources: [
      for (final s in honeyItem()['sources'] as List) SourceRef.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
  final puzzle = FiveCluesPuzzle.parse(record.payload, record.reveal);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_fiveclues');
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
          home: FiveCluesScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Future<void> guess(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('fiveclues-input')), text);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fiveclues-guess')));
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong guess brings out the next clue and saves progress', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('CLUE 1 OF 5'), findsOneWidget);
      expect(find.text('Name it now for 5 points'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiveclues-clue-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('fiveclues-clue-1')), findsNothing);

      await guess(tester, 'Nectar');
      expect(find.byKey(const ValueKey('fiveclues-clue-1')), findsOneWidget);
      expect(find.text('CLUE 2 OF 5'), findsOneWidget);
      expect(find.text('Name it now for 4 points'), findsOneWidget);
      expect(find.text('Nectar · not this one'), findsOneWidget);
      expect(find.text('1 guess so far'), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id)?['revealed'] == 2, reason: 'progress saved');

      await tester.tap(find.byKey(const ValueKey('fiveclues-next')));
      await tester.pumpAndSettle();
      expect(find.text('CLUE 3 OF 5'), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id)?['revealed'] == 3, reason: 'the pass is saved');
      expect((store.progress(id)!['guesses'] as List).length, 1, reason: 'a pass is not an attempt');
      await tearDownScreen(tester);
    });
  });

  testWidgets('a right answer scores the clue it came on and saves one result', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, isArchivePlay: true);
      await guess(tester, 'Sugar');
      await guess(tester, '  the honey! ');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Story found').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.points, 4);
      expect(result.maxPoints, 5);
      expect(result.attempts, 2);
      expect(result.isArchivePlay, isTrue);
      expect(result.note, 'Solved on clue 2 · 4 points');
      expect(result.shareLines, ['🔗 solved on clue 2', '🟥🟩⬜⬜⬜']);
      expect(find.text('Solved on clue 2 · 4 points'), findsWidgets);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('THE ANSWER'), findsOneWidget);
      expect(find.text(puzzle.answer), findsOneWidget);
      expect(find.text('You named it here'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiveclues-input')), findsNothing);
      expect(find.byKey(const ValueKey('fiveclues-see-result')), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('the same guess twice is refused and does not open a clue', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await guess(tester, 'Nectar');
      await guess(tester, 'nectar');
      expect(find.text('You have already tried “nectar”'), findsOneWidget);
      expect(find.text('CLUE 2 OF 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiveclues-clue-2')), findsNothing);
      await tearDownScreen(tester);
    });
  });

  testWidgets('giving up on the last clue reveals every link', (tester) async {
    await tester.runAsync(() async {
      var state = FiveCluesState.initial(puzzle);
      for (var i = 0; i < 4; i++) {
        state = state.pass();
      }
      await store.saveProgress(id, state.toJson());
      await pumpScreen(tester);
      expect(find.text('CLUE 5 OF 5'), findsOneWidget);
      expect(find.text('Give up'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fiveclues-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reveal the answer'));
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Not this time').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.points, 0);
      expect(result.attempts, 0);
      expect(result.shareLines, ['🔗 not solved', '🟥🟥🟥🟥🟥']);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('THE ANSWER'), findsOneWidget);
      expect(find.text('You named it here'), findsNothing);
      expect(find.textContaining('Its high sugar concentration'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SOURCES'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('made by several species of bees'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 10),
          solved: true,
          points: 3,
          maxPoints: 5,
          attempts: 2,
          note: 'Solved on clue 3 · 3 points',
        ),
      );
      await pumpScreen(tester);
      expect(find.text('THE ANSWER'), findsOneWidget);
      expect(find.text(puzzle.answer), findsOneWidget);
      expect(find.text('Solved on clue 3 · 3 points'), findsOneWidget, reason: 'the saved result speaks for the lost progress');
      expect(find.text('You named it here'), findsNothing);
      expect(find.byKey(const ValueKey('fiveclues-input')), findsNothing);
      expect(find.byKey(const ValueKey('fiveclues-guess')), findsNothing);
      expect(find.byKey(const ValueKey('fiveclues-reveal-4')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fiveclues-see-result')));
      await tester.pumpAndSettle();
      expect(find.text('Story found'), findsOneWidget);
      expect(find.text('The answer'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
