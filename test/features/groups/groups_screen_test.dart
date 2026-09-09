import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/groups/groups.dart';
import 'package:playthepaper/features/games/groups/groups_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:provider/provider.dart';

import '../../engines/groups/fixtures.dart';
import '../../support/pump_until.dart';

/// Every body runs under [WidgetTester.runAsync]: the screen saves progress
/// to Hive after each move, and that file I/O needs a real event loop.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('groups-2026-09-10-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: skyPayload(),
    reveal: skyReveal(),
    sources: [
      for (final s in skyItem()['sources'] as List) SourceRef.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
  final puzzle = GroupsPuzzle.parse(record.payload, record.reveal);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_groups');
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
          home: GroupsScreen(play: PlayContext(store: store, record: record, isArchivePlay: isArchivePlay)),
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

  Finder tile(String text) => find.byKey(ValueKey('groups-tile-${GroupsPuzzle.normalise(text)}'));
  Finder band(int index) => find.byKey(ValueKey('groups-band-$index'));

  Future<void> tapThenSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pickAndSubmit(WidgetTester tester, List<String> tiles) async {
    for (final t in tiles) {
      await tapThenSettle(tester, tile(t));
    }
    await tapThenSettle(tester, find.byKey(const ValueKey('groups-submit')));
  }

  testWidgets('shows twelve tiles and locks a group that is submitted', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (final t in puzzle.tiles) {
        expect(tile(t), findsOneWidget, reason: t);
      }
      expect(find.text('Mistakes 0 of 4'), findsOneWidget);
      expect(find.text('Planets'), findsNothing, reason: 'titles stay hidden until found');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('groups-submit'))).onPressed, isNull);

      await pickAndSubmit(tester, ['Venus', 'Mars', 'Jupiter', 'Saturn']);

      expect(band(0), findsOneWidget);
      expect(find.text('Planets'), findsOneWidget);
      expect(find.text('Venus · Mars · Jupiter · Saturn'), findsOneWidget);
      expect(find.text('That is a group.'), findsOneWidget);
      expect(tile('Venus'), findsNothing, reason: 'a found group leaves the board');
      expect(tile('Mercury'), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id)?['found']?.length == 1, reason: 'progress saved');
      expect(store.progress(id)!['mistakes'], 0);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a wrong submission costs a mistake and says when it is one away', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await pickAndSubmit(tester, ['Venus', 'Mars', 'Jupiter', 'Mercury']);
      expect(find.text('One away. Three of those belong together.'), findsOneWidget);
      expect(find.text('Mistakes 1 of 4'), findsOneWidget);
      expect(band(0), findsNothing);
      await pumpUntil(tester, () => store.progress(id)?['mistakes'] == 1, reason: 'mistake saved');

      await tapThenSettle(tester, find.byKey(const ValueKey('groups-clear')));
      await pickAndSubmit(tester, ['Venus', 'Mars', 'Lead', 'Tin']);
      expect(find.text('Not a group. That costs a mistake.'), findsOneWidget);
      expect(find.text('Mistakes 2 of 4'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('shuffle reorders the tiles without changing the answer', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      List<String> shown() {
        final positions = [for (final t in puzzle.tiles) (t, tester.getTopLeft(tile(t)))]
          ..sort((a, b) => a.$2.dy == b.$2.dy ? a.$2.dx.compareTo(b.$2.dx) : a.$2.dy.compareTo(b.$2.dy));
        return positions.map((p) => p.$1).toList();
      }

      final before = shown();
      expect(before, puzzle.tiles);
      await tapThenSettle(tester, find.byKey(const ValueKey('groups-shuffle')));
      final after = shown();
      expect(after, isNot(before));
      expect(after.toSet(), before.toSet());
      await pumpUntil(tester, () => (store.progress(id)?['order'] as List?)?.cast<String>().join() == after.join());
      await tearDownScreen(tester);
    });
  });

  testWidgets('the keyboard moves a cursor, picks tiles and submits', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      Future<void> key(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pumpAndSettle();
      }

      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.space);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.space);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.space);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.space);
      await key(LogicalKeyboardKey.enter);

      expect(find.text('Metals known to the ancients'), findsOneWidget);
      expect(tile('Mercury'), findsNothing);
      await pumpUntil(tester, () => store.progress(id)?['found']?.first == 1, reason: 'the metals were found');
      await tearDownScreen(tester);
    });
  });

  testWidgets('finding all three groups saves one result and shows it', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, isArchivePlay: true);
      await pickAndSubmit(tester, ['Sirius', 'Vega', 'Rigel', 'Altair']);
      await pickAndSubmit(tester, ['Venus', 'Mars', 'Jupiter', 'Mercury']);
      await tapThenSettle(tester, find.byKey(const ValueKey('groups-clear')));
      await pickAndSubmit(tester, ['Mercury', 'Lead', 'Tin', 'Copper']);
      await pickAndSubmit(tester, ['Venus', 'Mars', 'Jupiter', 'Saturn']);

      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Story found').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.attempts, 1);
      expect(result.note, 'Solved with 1 mistake');
      expect(result.shareLines, ['🟦🟦🟦🟦', '🟨🟨🟨🟨', '🟩🟩🟩🟩']);
      expect(result.isArchivePlay, isTrue);
      expect(find.text('Solved with 1 mistake'), findsWidgets);
      expect(find.text('The groups'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('groups-submit')), findsNothing);
      expect(find.text('All three groups found.'), findsWidgets);
      await tearDownScreen(tester);
    });
  });

  testWidgets('four mistakes end the game with every group shown', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (final wrong in [
        ['Venus', 'Mars', 'Lead', 'Tin'],
        ['Venus', 'Mars', 'Lead', 'Copper'],
        ['Venus', 'Mars', 'Tin', 'Copper'],
        ['Venus', 'Jupiter', 'Lead', 'Tin'],
      ]) {
        await tapThenSettle(tester, find.byKey(const ValueKey('groups-clear')));
        await pickAndSubmit(tester, wrong);
      }
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Not this time').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();
      final result = store.result(id)!;
      expect(result.solved, isFalse);
      expect(result.attempts, 4);
      expect(result.note, 'Found 0 of 3 groups');
      expect(result.shareLines, isEmpty);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Planets'), findsWidgets);
      expect(find.text('Bright stars'), findsWidgets);
      expect(find.text('Not found'), findsNWidgets(3));
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle reopens read-only with the groups and See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(
        puzzleId: id,
        completedAt: DateTime.utc(2026, 9, 10),
        solved: true,
        attempts: 0,
        note: 'Solved with no mistakes',
      ));
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.byKey(const ValueKey('groups-submit')), findsNothing);
      expect(find.byKey(const ValueKey('groups-shuffle')), findsNothing);
      expect(tile('Venus'), findsNothing);
      expect(find.text('Planets'), findsOneWidget);
      expect(find.text('Metals known to the ancients'), findsOneWidget);
      expect(find.text('The three groups in this puzzle.'), findsOneWidget);
      expect(find.text('Not found'), findsNothing);
      await tester.scrollUntilVisible(find.textContaining('first-magnitude stars'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('first-magnitude stars'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('See result'), -200, scrollable: find.byType(Scrollable).first);
      await tapThenSettle(tester, find.text('See result'));
      expect(find.text('Story found'), findsOneWidget);
      expect(find.text('The groups'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
