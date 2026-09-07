import 'dart:io';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/core/theme.dart';
import 'package:daypencil/features/games/letters/letters_screen.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// The store writes to disk, so every test body runs under [WidgetTester.runAsync].
void main() {
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('letters-2026-09-08-en-v1');
  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    dictionaryVersion: 'test',
    payload: const {'center': 'T', 'outer': 'ABCEHR', 'minLength': 4},
    reveal: const {
      'answers': ['BEAT', 'BRACHET', 'BREATH', 'TEACH'],
      'pangrams': ['BRACHET'],
      'maxScore': 26,
    },
  );
  const teaser = "Today's letters come from a story about a hunting hound.";
  const excerpt = 'A brachet, the old word for a scent hound, ran ahead of the riders.';
  final seeded = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    dictionaryVersion: 'test',
    payload: const {'center': 'T', 'outer': 'ABCEHR', 'minLength': 4, 'teaser': teaser},
    reveal: const {
      'answers': ['BEAT', 'BRACHET', 'BREATH', 'TEACH'],
      'pangrams': ['BRACHET'],
      'maxScore': 26,
      'storyId': 'hunt-1-hound',
      'excerpt': excerpt,
    },
    storyId: 'hunt-1-hound',
  );
  const story = Story(
    id: 'hunt-1-hound',
    headline: 'The hound that led the hunt',
    summary: 'A medieval word for a scent hound survives in a handful of place names.',
    publisher: 'Field Notes',
    url: 'https://example.com/brachet',
    publishedAt: '2026-09-07',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('daypencil_letters');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester, {PlayContext? play}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
        ],
        child: MaterialApp(
          theme: DaypencilTheme.light(),
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: LettersScreen(
            play: play ?? PlayContext(store: store, record: record),
          ),
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

  /// Lets the store finish writing, then renders what changed.
  Future<void> settle(WidgetTester tester) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  Future<void> tapLetters(WidgetTester tester, String word) async {
    for (final ch in word.split('')) {
      await tester.tap(find.bySemanticsLabel(RegExp('letter $ch\$')));
      await tester.pump();
    }
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Enter'));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
    await settle(tester);
  }

  testWidgets('tapping letters then Enter adds a found word and points', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);

      expect(find.text('Beginner · 0 points'), findsOneWidget);
      expect(find.bySemanticsLabel('centre letter T'), findsOneWidget);

      await tapLetters(tester, 'BEAT');
      await enter(tester);

      expect(find.text('+1 Good'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'BEAT'), findsOneWidget);
      expect(find.text('Good start · 1 point'), findsOneWidget);
      expect(find.text('You have found 1 word'), findsOneWidget);
      expect(store.progress(id)!['found'], ['BEAT']);
      expect(store.progress(id)!['outer'], 'ABCEHR');

      await tapLetters(tester, 'BEAT');
      await enter(tester);
      expect(find.text('Already found'), findsOneWidget);

      await tapLetters(tester, 'BEACH');
      await enter(tester);
      expect(find.text('Missing centre letter'), findsOneWidget);

      await tapLetters(tester, 'BRACHET');
      await enter(tester);
      expect(find.text('+14 Pangram!'), findsOneWidget);
      expect(find.widgetWithText(Chip, '★ BRACHET'), findsOneWidget);
      expect(find.text('Amazing · 15 points'), findsOneWidget);
      expect(store.progress(id)!['found'], ['BEAT', 'BRACHET']);

      await Future<void>.delayed(const Duration(milliseconds: 1700));
      await tester.pump();
      expect(find.text('+14 Pangram!'), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('physical keyboard types, deletes and submits', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);

      for (final key in [
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyX,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(find.bySemanticsLabel('Current word T E A C H X'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.bySemanticsLabel('Current word T E A C H'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(find.widgetWithText(Chip, 'TEACH'), findsOneWidget);
      expect(find.text('Solid · 5 points'), findsOneWidget);
      expect(store.progress(id)!['found'], ['TEACH']);
      semantics.dispose();
    });
  });

  testWidgets('restores progress and shuffle keeps the letters', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await store.saveProgress(id, {
        'found': ['TEACH', 'BEAT'],
        'finished': false,
        'outer': 'HRABCE',
      });
      await pumpScreen(tester);

      expect(find.text('Solid · 6 points'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'BEAT'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'TEACH'), findsOneWidget);

      await tester.tap(find.byTooltip('Shuffle'));
      await settle(tester);
      final outer = store.progress(id)!['outer'] as String;
      expect(outer.split('')..sort(), 'ABCEHR'.split(''));
      expect(store.progress(id)!['found'], ['TEACH', 'BEAT']);
      for (final ch in 'ABCEHR'.split('')) {
        expect(find.bySemanticsLabel('letter $ch'), findsOneWidget);
      }
      semantics.dispose();
    });
  });

  testWidgets('finish saves the result once and locks the board', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, {
        'found': ['BRACHET', 'TEACH'],
        'finished': false,
      });
      await pumpScreen(
        tester,
        play: PlayContext(store: store, record: record, isArchivePlay: true),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Finish'));
      await tester.pumpAndSettle();
      expect(find.text('Finish the puzzle?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep playing'));
      await tester.pumpAndSettle();
      expect(store.isCompleted(id), isFalse);

      await finish(tester);

      final result = store.result(id)!;
      expect(result.points, 19);
      expect(result.maxPoints, 26);
      expect(result.solved, isTrue);
      expect(result.isArchivePlay, isTrue);
      expect(result.shareLines, ['Genius · 2/4 words']);
      expect(find.text('Every word'), findsOneWidget);
      expect(find.text('✓ ★ BRACHET'), findsOneWidget);
      expect(find.text('BEAT'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);

      expect(find.text('Finished · the board is locked'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'See result'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Enter'), findsNothing);
      expect(find.text('✓ TEACH'), findsOneWidget);
      expect(store.progress(id)!['found'], ['BRACHET', 'TEACH']);
      expect(store.allResults().length, 1);
    });
  });

  testWidgets('a seeded puzzle shows the teaser before play and the excerpt after', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(
        tester,
        play: PlayContext(store: store, record: seeded, story: story),
      );
      expect(find.text("From today's stories · $teaser"), findsOneWidget);
      expect(find.text(excerpt), findsNothing);
      expect(find.text('Read the story'), findsNothing);

      await tapLetters(tester, 'BRACHET');
      await enter(tester);
      await finish(tester);

      expect(find.text('Every word'), findsOneWidget);
      expect(find.text(excerpt), findsOneWidget);
      expect(find.text('— Field Notes'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Read the story'), findsOneWidget);
      expect(find.text('✓ ★ BRACHET'), findsOneWidget);
      final rich = tester.widget<Text>(find.text(excerpt));
      final bold = <String>[];
      rich.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) bold.add(span.text!);
        return true;
      });
      expect(bold, ['brachet']);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Finished · the board is locked'), findsOneWidget);
      expect(find.text(excerpt), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Read the story'), findsOneWidget);
      expect(find.text('EVERY WORD'), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('an unseeded puzzle shows no teaser, and a seeded one without its story shows no link', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      expect(find.textContaining("From today's stories"), findsNothing);

      await store.saveProgress(id, {
        'found': ['BEAT'],
        'finished': false,
      });
      await pumpScreen(
        tester,
        play: PlayContext(store: store, record: seeded),
      );
      await finish(tester);
      expect(find.text(excerpt), findsOneWidget);
      expect(find.text('Read the story'), findsNothing);
    });
  });

  testWidgets('a completed puzzle opens read-only with See result', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await tapLetters(tester, 'BEAT');
      await enter(tester);
      await finish(tester);
      await pumpUntil(tester, () => find.byTooltip('Close').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      await pumpUntil(tester, () => store.progress(id)?['finished'] == true, reason: 'finished board saved');

      final challenge = store.result(id)!;
      await pumpScreen(
        tester,
        play: PlayContext(store: store, record: record, challenge: challenge),
      );

      expect(find.text('Good start · 1 point'), findsOneWidget);
      expect(find.text('Friend: 1 point'), findsOneWidget);
      expect(find.text('✓ BEAT'), findsOneWidget);
      expect(find.text('★ BRACHET'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Enter'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'See result'));
      await tester.pumpAndSettle();
      expect(find.text('Every word'), findsOneWidget);
      expect(find.text('Not this time'), findsOneWidget);
      semantics.dispose();
    });
  });
}
