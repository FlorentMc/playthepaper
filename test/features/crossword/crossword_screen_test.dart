import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/core/theme.dart';
import 'package:daypencil/engines/crossword/crossword_puzzle.dart';
import 'package:daypencil/features/games/crossword/crossword_screen.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/shared/widgets/letter_keyboard.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

const grid = ['##...', '#....', '.....', '....#', '...##'];
const solution = ['##FAN', '#TRUE', 'FRONT', 'REST#', 'YET##'];

/// Every body runs under [WidgetTester.runAsync] because the screen writes
/// progress to Hive after each letter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('crossword-2026-09-08-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: {
      'size': 5,
      'grid': grid,
      'clues': {
        for (final d in Direction.values)
          d.name: [
            for (final e in deriveEntries(grid))
              if (e.direction == d) {...e.toJson(), 'clue': 'Clue for ${e.label}'},
          ],
      },
    },
    reveal: {'solution': solution},
  );

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('daypencil_crossword');
    store = await LocalStore.open(subDir: dir.path);
  });

  setUp(() => store.clearAll());

  tearDownAll(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  /// The timer schedules a frame every second, so pumpAndSettle never returns.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: DaypencilTheme.light(),
          home: CrosswordScreen(play: PlayContext(store: store, record: record)),
        ),
      ),
    );
    await settle(tester);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(400, 20));
      await settle(tester);
    }
    expect(find.byType(BottomSheet), findsNothing);
  }

  Future<void> tearDownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Finder key(String label) => find.descendant(of: find.byType(LetterKeyboard), matching: find.text(label));

  testWidgets('tapping a cell then a key writes the letter and saves progress', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.textContaining('1 Across'), findsWidgets);
      expect(find.textContaining('Clue for 1 Across'), findsWidgets);

      await tester.tap(key('F'));
      await tester.pump();
      await tester.tap(key('A'));
      await tester.pump();
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'progress saved');
      final letters = store.progress(id)!['letters'] as String;
      expect(letters.substring(2, 4), 'FA');

      await tearDownScreen(tester);
    });
  });

  testWidgets('filling every cell correctly completes the puzzle once', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (final ch in 'FANTRUEFRONTRESTYET'.split('')) {
        await tester.tap(key(ch));
        await tester.pump();
      }
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.hints, 0);
      await pumpUntil(tester, () => find.text('All filled in').evaluate().isNotEmpty, reason: 'result screen shown');
      await settle(tester);
      expect(find.text('All filled in'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a completed puzzle opens read-only with See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: true, seconds: 61, hints: 1));
      await pumpScreen(tester);
      expect(find.text('See result'), findsOneWidget);
      expect(find.text('Solved in 1:01 · 1 hint'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
