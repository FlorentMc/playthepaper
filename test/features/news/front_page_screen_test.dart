import 'package:daypencil/content/content_repository.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/features/news/front_page_screen.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'news_test_support.dart';

void main() {
  late LocalStore store;
  final correctId = PuzzleId(game: GameKind.correct, date: kTestDate);
  final whereId = PuzzleId(game: GameKind.where, date: kTestDate);

  setUp(() async {
    store = await openTestStore();
  });

  tearDown(() => store.clearAll());

  ContentRepository repo() => ContentRepository(
        store: store,
        bundle: FakeBundle({'assets/content/editions/$kTestDateText.json': evergreenEditionJson('science-1')}),
        client: MockClient((_) async => http.Response('down', 503)),
      )..networkEnabled = false;

  Future<void> pump(WidgetTester tester, {String date = kTestDateText}) async {
    useTallViewport(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(harness(store, FrontPageScreen(dateText: date), repository: repo()));
    await settle(tester);
  }

  testWidgets('folds unplayed stories and reveals them on request', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      expect(find.text('The Front Page'), findsNWidgets(2));
      expect(find.text('THURSDAY 1 JANUARY 2026'), findsOneWidget);
      expect(find.text('Evergreen · Science'), findsOneWidget);
      for (var n = 1; n <= 3; n++) {
        expect(find.text('Story $n · not played yet'), findsOneWidget);
      }
      expect(find.textContaining('speed of light'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reveal').first);
      await tester.pumpAndSettle();
      expect(find.text('Story 1 · not played yet'), findsNothing);
      expect(find.textContaining('speed of light really means'), findsOneWidget);
      expect(find.text('Wikipedia · Read the story'), findsOneWidget);
      expect(find.text('Not played'), findsOneWidget);
      expect(find.text('Story 2 · not played yet'), findsOneWidget);

      await tester.tap(find.text('Reveal all'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not played yet'), findsNothing);
      expect(find.text('Reveal all'), findsNothing);
      expect(find.text('Not played'), findsNWidgets(3));
    });
  });

  testWidgets('shows results for played stories and shares a spoiler-free summary', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(puzzleId: correctId, completedAt: DateTime.utc(2026), solved: true, attempts: 2));
      await store.saveResult(GameResult(puzzleId: whereId, completedAt: DateTime.utc(2026), solved: false, distanceKm: 1234.4));
      await pump(tester);
      expect(find.textContaining('speed of light really means'), findsOneWidget);
      expect(find.text('You: Corrected on attempt 2'), findsOneWidget);
      expect(find.text('You: 1234 km away'), findsOneWidget);
      expect(find.text('Story 2 · not played yet'), findsOneWidget);
      expect(find.text('Share the edition'), findsOneWidget);
      expect(find.text('Back to today'), findsOneWidget);

      final manifest = await repo().edition(kTestDate);
      expect(
        frontPageShareText(manifest, store),
        'Daypencil · 1 Jan 2026\n'
        'Correct: Corrected on attempt 2\n'
        'The Number: Not played\n'
        'Where: 1234 km away\n'
        'https://daypencil.com/e/2026-01-01',
      );
    });
  });

  testWidgets('a bad date shows a message instead of crashing', (tester) async {
    await tester.runAsync(() async {
      await pump(tester, date: 'not-a-date');
      expect(find.text('No edition for not-a-date.'), findsOneWidget);
    });
  });
}
