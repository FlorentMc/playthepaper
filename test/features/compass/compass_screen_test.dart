import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/features/games/compass/compass_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// A distinct lowercase word for each index, to pad a synthetic rank list.
String _filler(int i) {
  var n = i;
  final out = StringBuffer('x');
  do {
    out.writeCharCode('a'.codeUnitAt(0) + n % 26);
    n ~/= 26;
  } while (n > 0);
  return out.toString();
}

/// The store writes to disk, so every test body runs under [WidgetTester.runAsync].
void main() {
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('compass-2026-09-10-en-v1');
  const size = 100;
  // With 100 ranked words: rank 1 is very close, 2..10 close, 11..100 warm.
  final ranks = <String, int>{'port': 1, 'dock': 2, 'ship': 3, 'boat': 20, 'pier': 50};
  for (var r = 1; r <= size; r++) {
    if (!ranks.containsValue(r)) ranks[_filler(r)] = r;
  }
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: const {'vocabularySize': size},
    reveal: {'target': 'harbor', 'ranks': ranks},
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_compass');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    final play = PlayContext(store: store, record: record);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: PaperTheme.light(),
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: CompassScreen(play: play),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final helpSheet = find.byType(BottomSheet);
    if (helpSheet.evaluate().isNotEmpty) {
      Navigator.of(tester.element(helpSheet)).pop();
      await tester.pumpAndSettle();
    }
  }

  Future<void> typeAndEnter(WidgetTester tester, String word) async {
    await tester.enterText(find.byType(TextField), word);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets('two guesses are ranked, sorted, saved, and the best is pinned', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.text('Your guesses appear here, nearest first.'), findsOneWidget);

      await typeAndEnter(tester, ' Boat ');
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'first guess saved');
      expect(find.bySemanticsLabel('boat, rank 20, warm'), findsOneWidget);
      expect(find.textContaining('Last: boat #20 · warm'), findsOneWidget);
      expect(find.text('BEST SO FAR'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'dock');
      await tester.tap(find.widgetWithText(FilledButton, 'Guess'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => (store.progress(id)?['guesses'] as List?)?.length == 2,
        reason: 'second guess saved',
      );
      await tester.pump();
      expect(find.bySemanticsLabel('dock, rank 2, close'), findsOneWidget);
      expect(find.bySemanticsLabel('boat, rank 20, warm'), findsOneWidget);
      expect(store.progress(id), {
        'guesses': [
          {'word': 'boat'},
          {'word': 'dock'},
        ],
      });
      expect(store.result(id), isNull);

      // The best guess is pinned above the rule; the earlier, weaker guess sits below it.
      final dockY = tester.getTopLeft(find.bySemanticsLabel('dock, rank 2, close')).dy;
      final boatY = tester.getTopLeft(find.bySemanticsLabel('boat, rank 20, warm')).dy;
      expect(dockY, lessThan(boatY));
      semantics.dispose();
    });
  });

  testWidgets('a far word, a repeat and a non-word are handled', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await typeAndEnter(tester, 'banana');
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'far guess saved');
      expect(find.bySemanticsLabel('banana, far'), findsOneWidget);

      await typeAndEnter(tester, 'BANANA');
      await tester.pump();
      expect(find.text('You already tried "banana"'), findsOneWidget);

      await typeAndEnter(tester, 'two words');
      await tester.pump();
      expect(find.text('One word, letters only'), findsOneWidget);
      expect((store.progress(id)!['guesses'] as List).length, 1);
      semantics.dispose();
    });
  });

  testWidgets('a hint reveals the word halfway to the best and is counted', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await typeAndEnter(tester, 'pier');
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'guess saved');
      await tester.tap(find.widgetWithText(TextButton, 'Hint'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => (store.progress(id)?['guesses'] as List?)?.length == 2,
        reason: 'hint saved',
      );
      await tester.pump();
      expect(find.bySemanticsLabel('xz, rank 25, warm, hint'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Hint (1)'), findsOneWidget);
      expect(store.progress(id), {
        'guesses': [
          {'word': 'pier'},
          {'word': 'xz', 'hint': true},
        ],
      });
      semantics.dispose();
    });
  });

  testWidgets('guessing the word completes the puzzle and keeps the guesses for review', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await typeAndEnter(tester, 'port');
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'guess saved');
      await typeAndEnter(tester, 'Harbor');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.attempts, 2);
      expect(result.hints, 0);
      expect(result.shareLines, ['🧭 solved in 2 guesses']);
      expect(result.note, 'Solved in 2 guesses');
      expect(find.text('The word'), findsOneWidget);
      expect(find.text('Nearest: port, dock, ship'), findsOneWidget);

      // Back from the result screen the board is read-only and lists the guesses.
      await tester.tap(find.byTooltip('Close'));
      await pumpUntil(tester, () => find.text('YOUR GUESSES').evaluate().isNotEmpty, reason: 'board locked for review');
      await tester.pumpAndSettle();
      expect(store.progress(id), {
        'guesses': [
          {'word': 'port'},
          {'word': 'harbor'},
        ],
      });
      expect(find.text('YOUR GUESSES'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'See result'), findsOneWidget);
      expect(find.bySemanticsLabel('harbor, the hidden word'), findsOneWidget);
      expect(find.bySemanticsLabel('port, rank 1, very close'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('a completed puzzle reopens read-only and lists the guesses', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 10, 8),
          solved: false,
          attempts: 2,
          hints: 1,
          shareLines: const ['🧭 gave up after 2 guesses, closest #3 · 1 hint'],
        ),
      );
      await store.saveProgress(id, {
        'guesses': [
          {'word': 'banana'},
          {'word': 'ship'},
          {'word': 'xz', 'hint': true},
        ],
        'gaveUp': true,
      });
      await pumpScreen(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('harbor'), findsOneWidget);
      expect(find.text('Not solved · 2 guesses before giving up'), findsOneWidget);
      expect(find.text('YOUR GUESSES'), findsOneWidget);
      expect(find.bySemanticsLabel('ship, rank 3, close'), findsOneWidget);
      expect(find.bySemanticsLabel('xz, rank 25, warm, hint'), findsOneWidget);
      expect(find.bySemanticsLabel('banana, far'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'See result'));
      await tester.pumpAndSettle();
      expect(find.text('The word'), findsOneWidget);
      expect(store.allResults().length, 1);
      semantics.dispose();
    });
  });

  testWidgets('giving up reveals the word unsolved', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await typeAndEnter(tester, 'ship');
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'guess saved');
      await tester.tap(find.widgetWithText(TextButton, 'Give up'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reveal the word'));
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await tester.pumpAndSettle();
      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.attempts, 1);
      expect(result.shareLines, ['🧭 gave up after 1 guess, closest #3']);
    });
  });
}
