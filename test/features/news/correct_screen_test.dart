import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/features/games/correct/correct_screen.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_until.dart';
import 'news_test_support.dart';

void main() {
  late LocalStore store;
  final record = evergreenRecord('science-1', GameKind.correct);

  setUp(() async {
    store = await openTestStore();
  });

  tearDown(() => store.clearAll());

  Future<void> pump(WidgetTester tester, {GameResult? challenge}) async {
    useTallViewport(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(harness(
      store,
      CorrectScreen(play: PlayContext(store: store, record: record, challenge: challenge)),
    ));
    await settleAndDismissHelp(tester);
  }

  Finder detail(String text) => find.widgetWithText(TextButton, text);
  Finder option(String text) => find.widgetWithText(OutlinedButton, 'Replace with $text');

  testWidgets('shows the banner, prompt, tappable details and evidence', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      expect(find.text('This dispatch contains one altered detail'), findsOneWidget);
      expect(find.text('Which detail is wrong?'), findsOneWidget);
      expect(find.text('EVIDENCE'), findsNWidgets(2));
      expect(detail('13 seconds'), findsOneWidget);
      expect(detail('1983'), findsOneWidget);
      expect(find.text('Attempt 1 of 3'), findsOneWidget);
    });
  });

  testWidgets('wrong picks strike out and count attempts; win on attempt 3', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.tap(detail('1983'));
      await settle(tester);
      expect(find.text('Not that one · 2 attempts left'), findsOneWidget);
      expect(detail('✕ 1983'), findsOneWidget);
      expect(store.progress(record.id)!['wrongDetails'], [1]);

      await tester.tap(detail('13 seconds'));
      await settle(tester);
      expect(find.text('What should it say instead?'), findsOneWidget);
      expect(option('1.3 seconds'), findsOneWidget);

      await tester.tap(option('3 minutes'));
      await settle(tester);
      expect(find.text('Not that one · 1 attempt left'), findsOneWidget);

      await tester.tap(option('1.3 seconds'));
      await settle(tester);

      final result = store.result(record.id);
      expect(result, isNotNull);
      expect(result!.solved, isTrue);
      expect(result.attempts, 3);
      expect(store.hasProgress(record.id), isFalse);
      expect(find.text('Corrected'), findsOneWidget);
      expect(find.text('The correction'), findsOneWidget);
      expect(find.textContaining('reaches Earth in about 1.3 seconds'), findsOneWidget);
      expect(find.text('Read the story'), findsOneWidget);
    });
  });

  testWidgets('three wrong picks lose the round', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.tap(detail('1983'));
      await pumpUntil(tester, () => store.progress(record.id) != null, reason: 'first pick saved');
      await tester.tap(detail('8.3 minutes'));
      await settle(tester);
      await tester.tap(detail('299,792,458 metres per second'));
      await pumpUntil(tester, () => store.result(record.id) != null && !store.hasProgress(record.id), reason: 'result saved');
      await settle(tester);
      final result = store.result(record.id);
      expect(result, isNotNull);
      expect(result!.solved, isFalse);
      expect(result.attempts, 3);
      expect(find.text('Not this time'), findsOneWidget);
    });
  });

  testWidgets('a completed puzzle opens read-only with See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(puzzleId: record.id, completedAt: DateTime.utc(2026), solved: true, attempts: 2));
      await pump(tester);
      expect(find.text('Corrected on attempt 2.'), findsOneWidget);
      expect(find.text('See result'), findsOneWidget);
      expect(find.text('Which detail is wrong?'), findsNothing);
      await tester.tap(find.text('See result'));
      await settle(tester);
      expect(find.text('Corrected'), findsOneWidget);
    });
  });

  testWidgets('shows the friend line for a challenge', (tester) async {
    await tester.runAsync(() async {
      final friend = GameResult(puzzleId: record.id, completedAt: DateTime.utc(2026), solved: true, attempts: 1);
      await pump(tester, challenge: friend);
      expect(find.text('Friend: Corrected on attempt 1'), findsOneWidget);
    });
  });
}
