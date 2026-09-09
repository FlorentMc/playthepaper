import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:playthepaper/features/games/crossword/crossword_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/shared/widgets/letter_keyboard.dart';
import 'package:playthepaper/storage/local_store.dart';
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

  /// The same puzzle with 5 Across (FRONT) and 1 Down (FROST) seeded from stories.
  const storyIds = {'5 Across': 'weather', '1 Down': 'farm'};
  final seededRecord = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    storyId: 'weather',
    payload: {
      ...record.payload,
      'clues': {
        for (final d in Direction.values)
          d.name: [
            for (final e in deriveEntries(grid))
              if (e.direction == d)
                {...e.toJson(), 'clue': 'Clue for ${e.label}', if (storyIds.containsKey(e.label)) 'storyId': storyIds[e.label]},
          ],
      },
      'teaser': 'Two of today\'s clues come from the news.',
    },
    reveal: {
      'solution': solution,
      'seeded': [
        {'label': '5 Across', 'storyId': 'weather', 'excerpt': 'A cold front swept across the country overnight.'},
        {'label': '1 Down', 'storyId': 'farm', 'excerpt': 'Frost covered the fields by dawn.'},
      ],
    },
  );
  const stories = [
    Story(id: 'weather', headline: 'Cold snap', summary: 's', publisher: 'The Gazette', url: 'https://example.com/cold', publishedAt: '2026-09-07'),
    Story(id: 'farm', headline: 'Early frost', summary: 's', publisher: 'Farm Weekly', url: 'https://example.com/frost', publishedAt: '2026-09-07'),
  ];

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_crossword');
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

  Future<void> pumpScreen(WidgetTester tester, {bool seeded = false, Size size = const Size(430, 900)}) async {
    tester.view.physicalSize = size;
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
          home: CrosswordScreen(
            play: seeded
                ? PlayContext(store: store, record: seededRecord, stories: stories)
                : PlayContext(store: store, record: record),
          ),
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
      expect(find.byIcon(Icons.newspaper), findsNothing);
      await tearDownScreen(tester);
    });
  });

  testWidgets('an unseeded puzzle shows no teaser or newspaper glyph', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.textContaining("From today's stories"), findsNothing);
      expect(find.byIcon(Icons.newspaper), findsNothing);
      await tearDownScreen(tester);
    });
  });

  testWidgets('a seeded puzzle shows the teaser and marks seeded clues', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, seeded: true, size: const Size(430, 1400));
      expect(find.text("From today's stories · Two of today's clues come from the news."), findsOneWidget);
      // The teaser icon plus one glyph per seeded clue in the list; 1 Across is selected and unseeded.
      expect(find.byIcon(Icons.newspaper), findsNWidgets(3));
      expect(find.bySemanticsLabel(RegExp(r"^5 Across, Clue for 5 Across, from today's stories\n")), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r"^1 Across, Clue for 1 Across\n")), findsOneWidget);

      await tester.tap(find.textContaining('Clue for 5 Across'));
      await tester.pump();
      expect(find.byIcon(Icons.newspaper), findsNWidgets(4));
      expect(find.bySemanticsLabel(RegExp(r"^5 Across: Clue for 5 Across, from today's stories\. Switch direction")), findsOneWidget);
      semantics.dispose();
      await tearDownScreen(tester);
    });
  });

  testWidgets('completing a seeded puzzle reveals the stories behind the seeded entries', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, seeded: true);
      for (final ch in 'FANTRUEFRONTRESTYET'.split('')) {
        await tester.tap(key(ch));
        await tester.pump();
      }
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text("From today's stories").evaluate().isNotEmpty, reason: 'reveal shown');
      await settle(tester);
      expect(find.text('All filled in'), findsOneWidget);
      expect(find.text('5 Across · FRONT'), findsOneWidget);
      expect(find.text('1 Down · FROST'), findsOneWidget);
      expect(find.textContaining('A cold front swept across the country overnight.'), findsOneWidget);
      expect(find.textContaining('Frost covered the fields by dawn.'), findsOneWidget);
      expect(find.text('The Gazette · Read the story'), findsOneWidget);
      expect(find.text('Farm Weekly · Read the story'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });

  testWidgets('See result on a completed seeded puzzle shows the same reveal', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: true, seconds: 61, hints: 0));
      await pumpScreen(tester, seeded: true);
      expect(find.text("From today's stories · Two of today's clues come from the news."), findsOneWidget);
      await tester.tap(find.text('See result'));
      await pumpUntil(tester, () => find.text("From today's stories").evaluate().isNotEmpty, reason: 'reveal shown');
      await settle(tester);
      expect(find.text('5 Across · FRONT'), findsOneWidget);
      expect(find.text('Farm Weekly · Read the story'), findsOneWidget);
      await tearDownScreen(tester);
    });
  });
}
