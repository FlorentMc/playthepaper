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
