import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/uncover/uncover.dart';
import 'package:playthepaper/features/games/uncover/uncover_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../engines/uncover/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen writes progress
/// to Hive after each guess, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('uncover-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: boatPayload(),
    reveal: boatReveal(),
    sources: [
      for (final s in boatItem()['sources'] as List) SourceRef.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
  final puzzle = boatPuzzle();

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_uncover');
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
          home: UncoverScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Future<void> guess(WidgetTester tester, String word) async {
    await tester.enterText(find.byKey(const ValueKey('uncover-field')), word);
    await tester.tap(find.byKey(const ValueKey('uncover-guess')));
    await tester.pumpAndSettle();
  }

  int savedGuesses() => (store.progress(id)?['guesses'] as List?)?.length ?? 0;

  /// The story as the player sees it, blocks and all.
  String story(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('uncover-text')))
      .textSpan!
      .toPlainText(includeSemanticsLabels: false);

  testWidgets('a guess opens every place the word appears and is saved', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(story(tester), contains('▇▇▇'), reason: 'the text starts blanked out');
      expect(story(tester), isNot(contains('hull')));

      await guess(tester, 'hulls');
      expect(story(tester), contains('until a ▇▇▇▇▇ hull with'));
      expect(find.text('“hulls” appears 1 time.'), findsOneWidget);
      expect(find.textContaining('1 of 49 words uncovered · 1 guess'), findsOneWidget);
      await pumpUntil(tester, () => savedGuesses() == 1, reason: 'progress saved');

      await tester.enterText(find.byKey(const ValueKey('uncover-field')), 'sheet');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('“sheet” appears 2 times.'), findsOneWidget, reason: 'Enter submits the guess');
      expect(find.textContaining('3 of 49 words uncovered · 2 guesses'), findsOneWidget);
      await pumpUntil(tester, () => savedGuesses() == 2, reason: 'second guess saved');
      await tearDownScreen(tester);
    });
  });

  testWidgets('the subject stays shut when its own words are guessed', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await guess(tester, 'paper');
      expect(find.text('“paper” is not in the text.'), findsOneWidget);
      expect(story(tester), isNot(contains('paper')));
      expect(story(tester), startsWith('A ▇▇▇ ▇▇▇ is a ▇▇▇ ▇▇▇▇▇▇ from one'));
      expect(find.textContaining('0 of 49 words uncovered · 1 guess'), findsOneWidget);
      expect(store.result(id), isNull);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a hint is shown and counted', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.text('Hint (3)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('uncover-hint')));
      await tester.pumpAndSettle();
      expect(find.text('Hint (2)'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Hint 1: ${puzzle.hints.first}'), 200,
          scrollable: find.byType(Scrollable).first);
      await pumpUntil(tester, () => store.progress(id)?['hints'] == 1, reason: 'hint saved');
      await tearDownScreen(tester);
    });
  });

  testWidgets('naming the subject finishes the puzzle and saves the result once', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, isArchivePlay: true);
      await guess(tester, 'hull');
      await guess(tester, 'the paper boats');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Story found').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.attempts, 2);
      expect(result.hints, 0);
      expect(result.points, 10);
      expect(result.maxPoints, 10);
      expect(result.isArchivePlay, isTrue);
      expect(result.note, 'Uncovered in 2 guesses');
      expect(result.shareLines, ['🔎 uncovered in 2 guesses', '🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩']);
      expect(find.text('Uncovered in 2 guesses'), findsWidgets);
      expect(find.text('The subject'), findsOneWidget);
      expect(find.text('Paper Boat'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await pumpUntil(tester, () => find.text('THE SUBJECT').evaluate().isNotEmpty, reason: 'back on the board');
      await tester.pumpAndSettle();
      expect(story(tester), boatText, reason: 'the whole text is shown');
      expect(find.byKey(const ValueKey('uncover-field')), findsNothing);
      expect(find.byKey(const ValueKey('uncover-see-result')), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with the text and See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(
        puzzleId: id,
        completedAt: DateTime.utc(2026, 9, 10),
        solved: false,
        attempts: 12,
        hints: 3,
        points: 0,
        maxPoints: 10,
        note: 'Not uncovered · 12 guesses · 3 hints',
      ));
      await store.saveProgress(id, UncoverState.initial(puzzle).submit('hull').giveUp().toJson());
      await pumpScreen(tester);
      expect(find.text('THE SUBJECT'), findsOneWidget);
      expect(find.text('Paper Boat'), findsOneWidget);
      expect(find.text('Not uncovered · 12 guesses · 3 hints'), findsOneWidget);
      expect(find.byKey(const ValueKey('uncover-field')), findsNothing);
      expect(find.byKey(const ValueKey('uncover-hint')), findsNothing);
      expect(story(tester), boatText);
      await tester.scrollUntilVisible(find.text('SOURCES'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('A paper boat is a toy boat made out of paper.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('uncover-see-result')));
      await tester.pumpAndSettle();
      expect(find.text('Not this time'), findsOneWidget);
      expect(find.text('The subject'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
