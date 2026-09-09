import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/features/games/word/word_dictionary.dart';
import 'package:playthepaper/features/games/word/word_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/shared/widgets/letter_keyboard.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// The store writes to disk, so every test body runs under [WidgetTester.runAsync].
void main() {
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('word-2026-09-08-en-v1');
  final plain = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    dictionaryVersion: 'enable1-2026-09',
    payload: const {'length': 6, 'firstLetter': 'S', 'maxGuesses': 6},
    reveal: const {'answer': 'STREAM'},
  );
  const teaser = "Today's word comes from a story about the deep sea.";
  const excerpt = 'A stream of cold water, the researchers found, runs along the trench floor.';
  final seeded = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    dictionaryVersion: 'enable1-2026-09',
    payload: const {'length': 6, 'firstLetter': 'S', 'maxGuesses': 6, 'teaser': teaser},
    reveal: const {'answer': 'STREAM', 'storyId': 'nature-1-trench', 'excerpt': excerpt},
    storyId: 'nature-1-trench',
  );
  const story = Story(
    id: 'nature-1-trench',
    headline: 'A river at the bottom of the sea',
    summary: 'Researchers mapped a current running along the floor of the trench.',
    publisher: 'Ocean Weekly',
    url: 'https://example.com/trench',
    publishedAt: '2026-09-07',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_word');
    store = await LocalStore.open(subDir: dir.path);
    WordDictionary.debugOverride = {'STREAM', 'STRAND', 'STRIDE', 'TRAINS'};
  });

  tearDown(() async {
    WordDictionary.debugOverride = null;
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester, {GameResult? challenge, PuzzleRecord? record, Story? story}) async {
    final play = PlayContext(store: store, record: record ?? plain, challenge: challenge, story: story);
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
          home: WordScreen(play: play),
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

  Finder key(String label) => find.descendant(of: find.byType(LetterKeyboard), matching: find.text(label));

  Future<void> type(WidgetTester tester, String letters) async {
    for (final ch in letters.split('')) {
      await tester.tap(key(ch));
      await tester.pump();
    }
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.tap(key('ENTER'));
    await tester.pumpAndSettle();
  }

  /// Lets the store finish writing, then renders what changed.
  Future<void> settle(WidgetTester tester) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets('typing a valid word on the keyboard adds a submitted row with feedback', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.bySemanticsLabel('Row 1, letter 1, S, given'), findsOneWidget);

      await type(tester, 'TRAND');
      expect(find.bySemanticsLabel('Row 1, letter 6, D'), findsOneWidget);
      await enter(tester);
      await settle(tester);

      expect(find.bySemanticsLabel('Row 1, letter 1, S, in the word and in place'), findsOneWidget);
      expect(find.bySemanticsLabel('Row 1, letter 4, A, in the word, wrong place'), findsOneWidget);
      expect(find.bySemanticsLabel('Row 1, letter 6, D, not in the word'), findsOneWidget);
      expect(find.bySemanticsLabel('Row 2, letter 1, S, given'), findsOneWidget);
      expect(store.progress(id), {
        'guesses': ['STRAND'],
      });
      expect(store.result(id), isNull);
      semantics.dispose();
    });
  });

  testWidgets('backspace never removes the given first letter', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      await type(tester, 'TR');
      for (var i = 0; i < 3; i++) {
        await tester.tap(key('⌫'));
        await tester.pump();
      }
      expect(find.bySemanticsLabel('Row 1, letter 1, S, given'), findsOneWidget);
      expect(find.bySemanticsLabel('Row 1, letter 2, empty'), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('an invalid guess shows the reason and is not submitted', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await type(tester, 'TRA');
      await enter(tester);
      expect(find.text('Not enough letters'), findsOneWidget);
      expect(store.progress(id), isNull);

      await type(tester, 'XYZ');
      await enter(tester);
      expect(find.text('Not in the word list'), findsOneWidget);
      await settle(tester);
      expect(store.progress(id), isNull);
    });
  });

  testWidgets('guessing the answer saves the result once and shows the result screen', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await type(tester, 'TRAND');
      await enter(tester);
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'first guess saved');
      await type(tester, 'TREAM');
      await enter(tester);
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Word found').evaluate().isNotEmpty, reason: 'result screen shown');
      await settle(tester);

      final result = store.result(id);
      expect(result, isNotNull);
      expect(result!.solved, isTrue);
      expect(result.attempts, 2);
      expect(result.shareLines, ['🟩🟩🟩🟨⬜⬜', '🟩🟩🟩🟩🟩🟩']);
      expect(store.hasProgress(id), isFalse);
      expect(find.text('Word found'), findsOneWidget);
      expect(find.text('The word'), findsOneWidget);
      expect(find.text('STREAM'), findsOneWidget);
    });
  });

  testWidgets('six wrong guesses lose and reveal the answer', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      for (var i = 0; i < 6; i++) {
        await type(tester, 'TRAND');
        await enter(tester);
        if (i < 5) {
          await pumpUntil(
            tester,
            () => (store.progress(id)?['guesses'] as List?)?.length == i + 1,
            reason: 'guess ${i + 1} saved',
          );
        }
      }
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Not this time').evaluate().isNotEmpty, reason: 'result screen shown');
      await settle(tester);
      final result = store.result(id);
      expect(result, isNotNull);
      expect(result!.solved, isFalse);
      expect(result.attempts, 6);
      expect(find.text('Not this time'), findsOneWidget);
      expect(find.text('STREAM'), findsOneWidget);
    });
  });

  testWidgets('a saved game is restored and a finished one is read-only', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, {
        'guesses': ['STRAND'],
      });
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.bySemanticsLabel('Row 1, letter 4, A, in the word, wrong place'), findsOneWidget);
      expect(find.bySemanticsLabel('Row 2, letter 1, S, given'), findsOneWidget);
      semantics.dispose();

      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 8),
          solved: true,
          attempts: 2,
          shareLines: const ['🟩🟩🟩🟨⬜⬜', '🟩🟩🟩🟩🟩🟩'],
        ),
      );
      await pumpScreen(tester);
      expect(find.byType(LetterKeyboard), findsNothing);
      expect(find.text('STREAM'), findsOneWidget);
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Word found'), findsOneWidget);
    });
  });

  testWidgets('the help example renders three marked tiles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PaperTheme.light(),
        home: Scaffold(body: Builder(builder: WordScreen.help.example!)),
      ),
    );
    expect(WordScreen.help.paragraphs, hasLength(3));
    expect(find.text('Right place'), findsOneWidget);
    expect(find.text('Wrong place'), findsOneWidget);
    expect(find.text('Not in word'), findsOneWidget);
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('a seeded puzzle shows the teaser above the board and nothing else gives the story away', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, record: seeded, story: story);
      expect(find.text("From today's stories · $teaser"), findsOneWidget);
      expect(find.text(excerpt), findsNothing);
      expect(find.text('Read the story'), findsNothing);

      await pumpScreen(tester);
      expect(find.textContaining("From today's stories"), findsNothing);
    });
  });

  testWidgets('the reveal shows the excerpt and the story link after play', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester, record: seeded, story: story);
      await type(tester, 'TREAM');
      await enter(tester);
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Word found').evaluate().isNotEmpty, reason: 'result screen shown');
      await settle(tester);

      expect(find.text('The word'), findsOneWidget);
      expect(find.text('STREAM'), findsOneWidget);
      expect(find.text(excerpt), findsOneWidget);
      expect(find.text('— Ocean Weekly'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Read the story'), findsOneWidget);
      final rich = tester.widget<Text>(find.text(excerpt));
      final bold = <String>[];
      rich.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) bold.add(span.text!);
        return true;
      });
      expect(bold, ['stream']);
    });
  });

  testWidgets('a finished seeded board shows the excerpt, and no link without the story', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 8),
          solved: true,
          attempts: 2,
          shareLines: const ['🟩🟩🟩🟨⬜⬜', '🟩🟩🟩🟩🟩🟩'],
        ),
      );
      await pumpScreen(tester, record: seeded, story: story);
      expect(find.byType(LetterKeyboard), findsNothing);
      expect(find.text('STREAM'), findsOneWidget);
      expect(find.text(excerpt), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Read the story'), findsOneWidget);
      expect(find.text("From today's stories · $teaser"), findsOneWidget);

      await pumpScreen(tester, record: seeded);
      expect(find.text(excerpt), findsOneWidget);
      expect(find.text('Read the story'), findsNothing);
      await tester.tap(find.text('See result'));
      await tester.pumpAndSettle();
      expect(find.text('Word found'), findsOneWidget);
      expect(find.text(excerpt), findsOneWidget);
    });
  });

  testWidgets('a challenge summary is shown above the board', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(
        tester,
        challenge: GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: true, attempts: 3),
      );
      expect(find.text('Friend: Solved in 3/6'), findsOneWidget);
    });
  });
}
