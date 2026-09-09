import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/linked/linked.dart';
import 'package:playthepaper/features/games/linked/linked_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../engines/linked/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each answer, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('linked-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: flagPayload(),
    reveal: flagReveal(),
    sources: [
      for (final s in flagItem()['sources'] as List) SourceRef.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
  final puzzle = LinkedPuzzle.parse(record.payload, record.reveal);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_linked');
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
          home: LinkedScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  /// Brings the running score at the head of the page back into view.
  Future<void> scrollToTop(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pumpAndSettle();
  }

  Future<void> answerSet(WidgetTester tester, int index, String text) async {
    await scrollTo(tester, find.byKey(ValueKey('linked-set-$index-check')));
    await tester.enterText(find.byKey(ValueKey('linked-set-$index-input')), text);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('linked-set-$index-check')));
    await tester.pumpAndSettle();
  }

  Future<void> answerFinal(WidgetTester tester, String text) async {
    await scrollTo(tester, find.byKey(const ValueKey('linked-final-guess')));
    await tester.enterText(find.byKey(const ValueKey('linked-final-input')), text);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('linked-final-guess')));
    await tester.pumpAndSettle();
  }

  testWidgets('a right answer locks a set, and a hint costs a point', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('0 OF 3 SETS SOLVED'), findsOneWidget);
      expect(find.text('Worth 10 points now'), findsOneWidget);
      expect(find.textContaining('Chlorophyll'), findsOneWidget);

      await answerSet(tester, 0, 'blue');
      expect(find.byKey(const ValueKey('linked-set-0-input')), findsOneWidget, reason: 'a wrong answer leaves the set open');
      await answerSet(tester, 0, '  the GREEN! ');
      expect(find.text('Solved'), findsOneWidget);
      expect(find.byKey(const ValueKey('linked-set-0-input')), findsNothing);
      await pumpUntil(tester, () => (store.progress(id)?['sets'] as List?)?[0].length == 2, reason: 'progress saved');
      await scrollToTop(tester);
      expect(find.text('1 OF 3 SETS SOLVED'), findsOneWidget);

      await scrollTo(tester, find.byKey(const ValueKey('linked-set-1-hint')));
      await tester.tap(find.byKey(const ValueKey('linked-set-1-hint')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show it'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hint: The colour of snow'), findsOneWidget);
      await pumpUntil(tester, () => (store.progress(id)?['hints'] as List?)?[1] == true, reason: 'hint saved');
      await scrollToTop(tester);
      expect(find.text('Worth 9 points now'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('naming the link scores the puzzle and saves one result', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(
        id,
        LinkedState.initial(puzzle).guessSet(0, 'Green').guessSet(1, 'White').guessSet(2, 'Orange').toJson(),
      );
      await pumpScreen(tester, isArchivePlay: true);
      expect(find.text('3 OF 3 SETS SOLVED'), findsOneWidget);

      await answerFinal(tester, 'the flag of France');
      expect(find.text('1 wrong so far'), findsOneWidget);
      await scrollToTop(tester);
      expect(find.text('Worth 9 points now'), findsOneWidget);
      await answerFinal(tester, '  IRISH FLAG! ');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Story found').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.points, 9);
      expect(result.maxPoints, 10);
      expect(result.hints, 0);
      expect(result.isArchivePlay, isTrue);
      expect(result.note, 'Solved · 9 of 10 · 1 wrong guess');
      expect(result.shareLines, ['🔗 9/10', '🟩🟩🟩 → 🟩']);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('LINKED'), findsOneWidget);
      expect(find.text('THE LINK'), findsOneWidget);
      expect(find.text(puzzle.finalAnswer), findsOneWidget);
      expect(find.byKey(const ValueKey('linked-final-input')), findsNothing);
      expect(find.byKey(const ValueKey('linked-see-result')), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('giving up reveals every answer and scores nothing', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('linked-giveup')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reveal it all'));
      await tester.pumpAndSettle();
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Not this time').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.points, 0);
      expect(result.shareLines, ['🔗 0/10', '🟥🟥🟥 → 🟥']);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('THE ANSWERS'), findsOneWidget);
      expect(find.text('Green'), findsOneWidget);
      expect(find.text('You missed this'), findsNWidgets(3));
      expect(find.textContaining('Green lies between cyan'), findsOneWidget);
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
          points: 8,
          maxPoints: 10,
          hints: 1,
          note: 'Solved · 8 of 10 · 1 hint',
        ),
      );
      await pumpScreen(tester);
      expect(find.text(puzzle.finalAnswer), findsOneWidget);
      expect(find.text('LINKED'), findsOneWidget);
      expect(find.text('Solved · 8 of 10 · 1 hint'), findsOneWidget, reason: 'the saved result speaks for the lost progress');
      expect(find.text('You missed this'), findsNothing);
      expect(find.byKey(const ValueKey('linked-set-0-input')), findsNothing);
      expect(find.byKey(const ValueKey('linked-giveup')), findsNothing);
      expect(find.byKey(const ValueKey('linked-reveal-2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('linked-see-result')));
      await tester.pumpAndSettle();
      expect(find.text('Story found'), findsOneWidget);
      expect(find.text('The links'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
