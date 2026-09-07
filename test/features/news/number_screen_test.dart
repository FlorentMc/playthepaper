import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/features/games/number/number_screen.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'news_test_support.dart';

void main() {
  late LocalStore store;
  final record = evergreenRecord('science-1', GameKind.number);

  setUp(() async {
    store = await openTestStore();
  });

  tearDown(() => store.clearAll());

  Future<void> pump(WidgetTester tester, {GameResult? challenge}) async {
    useTallViewport(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(harness(
      store,
      NumberScreen(play: PlayContext(store: store, record: record, challenge: challenge)),
    ));
    await settleAndDismissHelp(tester);
  }

  testWidgets('shows the question, the comparison, a slider and a field in sync', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      expect(find.text('How many bones are in the adult human skeleton?'), findsOneWidget);
      expect(find.text('FOR SCALE'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('250 bones'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '206');
      await settle(tester);
      expect(find.text('206 bones'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 206);
      expect(store.progress(record.id)!['value'], 206);

      await tester.enterText(find.byType(TextField), '999');
      await settle(tester);
      expect(find.text('Between 100 and 400'), findsOneWidget);
      expect(find.text('206 bones'), findsOneWidget);
    });
  });

  testWidgets('dragging the slider updates the field', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(-300, 0));
      await settle(tester);
      final value = tester.widget<Slider>(slider).value;
      expect(value, lessThan(250));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, value.toStringAsFixed(0));
    });
  });

  testWidgets('submitting scores the estimate and shows the reveal', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '226');
      await settle(tester);
      await tester.tap(find.text('Submit estimate'));
      await settle(tester);

      final result = store.result(record.id);
      expect(result, isNotNull);
      expect(result!.errorPct, closeTo(9.7, 0.1));
      expect(result.solved, isTrue);
      expect(find.text('Estimate in'), findsOneWidget);
      expect(find.text('The real figure'), findsOneWidget);
      expect(find.text('The real figure: 206 bones'), findsOneWidget);
      expect(find.text('Your estimate: 226 bones · 10% off'), findsOneWidget);
      expect(find.text('Read the story'), findsOneWidget);
    });
  });

  testWidgets('a completed puzzle opens read-only', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(puzzleId: record.id, completedAt: DateTime.utc(2026), solved: false, errorPct: 55));
      await pump(tester);
      expect(find.text('55% off'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.text('See result'));
      await settle(tester);
      expect(find.text('Not this time'), findsOneWidget);
      expect(find.text('Your estimate was 55% off'), findsOneWidget);
    });
  });

  testWidgets('shows the friend line for a challenge', (tester) async {
    await tester.runAsync(() async {
      final friend = GameResult(puzzleId: record.id, completedAt: DateTime.utc(2026), solved: true, errorPct: 4);
      await pump(tester, challenge: friend);
      expect(find.text('Friend: 4% off'), findsOneWidget);
    });
  });
}
