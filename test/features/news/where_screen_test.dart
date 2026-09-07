import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/engines/where/where_engine.dart';
import 'package:daypencil/features/games/where/where_screen.dart';
import 'package:daypencil/features/games/where/world_map.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'news_test_support.dart';

void main() {
  late LocalStore store;
  final record = evergreenRecord('science-1', GameKind.where);

  setUp(() async {
    store = await openTestStore();
  });

  tearDown(() => store.clearAll());

  Future<void> pump(WidgetTester tester, {GameResult? challenge}) async {
    useTallViewport(tester);
    // Both assets decode off the main isolate; have them ready before pumping.
    await LandShapes.load();
    await WhereScreen.places();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(harness(
      store,
      WhereScreen(play: PlayContext(store: store, record: record, challenge: challenge)),
    ));
    await settleAndDismissHelp(tester);
    await settle(tester);
  }

  test('LandShapes.parse reads polygons and multipolygons', () {
    final land = LandShapes.parse({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [0, 0],
                [10, 0],
                [10, 10],
                [0, 0],
              ],
            ],
          },
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'MultiPolygon',
            'coordinates': [
              [
                [
                  [20, 20],
                  [30, 20],
                  [30, 30],
                  [20, 20],
                ],
              ],
            ],
          },
        },
      ],
    });
    expect(land.rings.length, 2);
    expect(land.rings.first.first, const Offset(0, 0));
  });

  test('projection round-trips', () {
    const size = Size(400, 200);
    final p = projectLatLon(48.9, 2.3, size);
    final back = unprojectPoint(p, size);
    expect(back.lat, closeTo(48.9, 1e-9));
    expect(back.lon, closeTo(2.3, 1e-9));
    expect(projectLatLon(90, -180, size), Offset.zero);
    expect(projectLatLon(-90, 180, size), const Offset(400, 200));
  });

  testWidgets('shows the clues and the map, and a tap places the pin', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      expect(find.text('CLUES'), findsOneWidget);
      expect(find.textContaining('27 km circular tunnel'), findsOneWidget);
      expect(find.text('Pin: tap the map to place it'), findsOneWidget);
      final submit = find.widgetWithText(FilledButton, 'Submit pin');
      expect(tester.widget<FilledButton>(submit).enabled, isFalse);

      await tester.tap(find.byType(WorldMap));
      await settle(tester);
      expect(find.text('Pin: 0.0°N, 0.0°E'), findsOneWidget);
      expect(store.progress(record.id)!['lat'], 0);
      expect(tester.widget<FilledButton>(submit).enabled, isTrue);
    });
  });

  testWidgets('choosing from the list places the pin; submitting scores the distance', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.tap(find.text('Choose from a list'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Search places'), 'genev');
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Geneva'));
      await settle(tester);
      expect(find.text('Pin: 46.2°N, 6.1°E'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Submit pin'));
      await settle(tester);

      final result = store.result(record.id);
      expect(result, isNotNull);
      expect(result!.solved, isTrue);
      expect(result.distanceKm, lessThan(20));
      expect(store.hasProgress(record.id), isFalse);
      expect(find.text('Pin placed'), findsOneWidget);
      expect(find.text('The place'), findsOneWidget);
      expect(find.textContaining('CERN, Meyrin, near Geneva ·'), findsOneWidget);
      expect(find.textContaining('within 250 km'), findsOneWidget);
      expect(find.text('Read the story'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Target'), findsOneWidget);
      expect(find.textContaining('km away'), findsOneWidget);
    });
  });

  testWidgets('a pin far away is not solved', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.tap(find.byType(WorldMap));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Submit pin'));
      await settle(tester);
      final result = store.result(record.id)!;
      expect(result.solved, isFalse);
      expect(result.distanceKm, closeTo(haversineKm(0, 0, 46.233, 6.056), 1));
      expect(find.text('Not this time'), findsOneWidget);
    });
  });

  testWidgets('a completed puzzle opens read-only with the target shown', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(puzzleId: record.id, completedAt: DateTime.utc(2026), solved: true, distanceKm: 120));
      await pump(tester);
      expect(find.text('120 km away'), findsOneWidget);
      expect(find.text('Target'), findsOneWidget);
      expect(find.text('Submit pin'), findsNothing);
      await tester.tap(find.text('See result'));
      await settle(tester);
      expect(find.text('Pin placed'), findsOneWidget);
    });
  });
}
