import 'dart:io';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_result.dart';
import 'package:playthepaper/core/puzzle_id.dart';
import 'package:playthepaper/core/theme.dart';
import 'package:playthepaper/features/games/quiz/quiz_screen.dart';
import 'package:playthepaper/features/play/play_context.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/pump_until.dart';

/// The store writes to disk, so every test body runs under [WidgetTester.runAsync].
void main() {
  late Directory dir;
  late LocalStore store;
  final id = PuzzleId.parse('quiz-2026-09-08-en-v1');

  const prompts = [
    'How much does a blue whale\'s heart weigh?',
    'Which is the tallest waterfall in the world?',
    'How many moons does Mars have?',
    'In which century did the cuckoo clock appear?',
    'Which ocean is the deepest?',
  ];
  const options = [
    ['18 kg', '180 kg', '1,800 kg', '18,000 kg'],
    ['Niagara', 'Angel Falls', 'Victoria', 'Iguazu'],
    ['One', 'Two', 'Three', 'Four'],
    ['16th', '17th', '18th', '19th'],
    ['Atlantic', 'Indian', 'Pacific', 'Arctic'],
  ];
  const storyIds = ['whale', 'falls', 'mars', 'clock', 'ocean'];
  const answers = [1, 1, 1, 1, 2];
  const explanations = [
    'About 180 kg, the largest heart known. When the whale dives it can slow to two beats a minute.',
    'Angel Falls drops 979 metres. The water turns to mist before it reaches the ground.',
    'Phobos and Deimos, both small and lumpy. Phobos is slowly spiralling inwards.',
    'The 17th century, in the Black Forest. The cuckoo call came a little later.',
    'The Pacific, at the Mariana Trench. Its deepest point is nearly 11 kilometres down.',
  ];

  final record = PuzzleRecord(
    id: id,
    locale: 'en-GB',
    contentVersion: 1,
    scoringVersion: 1,
    payload: {
      'questions': [
        for (var i = 0; i < 5; i++) {'prompt': prompts[i], 'options': options[i], 'storyId': storyIds[i]},
      ],
      'wagerQuestion': 4,
    },
    reveal: const {'answers': answers, 'explanations': explanations},
  );

  final stories = [
    for (final s in storyIds.take(4))
      Story(
        id: s,
        headline: 'A story about $s',
        summary: 'Two sentences about $s. That is all.',
        publisher: 'The Paper',
        url: 'https://example.com/$s',
        publishedAt: '2026-09-07',
      ),
  ];

  /// The right option of each question, and one wrong option.
  String right(int q) => options[q][answers[q]];
  String wrong(int q) => options[q][(answers[q] + 1) % 4];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_quiz');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    GameResult? challenge,
    void Function(GameResult)? onCompleted,
    double height = 1600,
  }) async {
    tester.view.physicalSize = Size(800, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final play = PlayContext(
      store: store,
      record: record,
      stories: stories,
      challenge: challenge,
      onCompleted: onCompleted,
    );
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
          home: QuizScreen(play: play),
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

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  List<Object?> savedAnswers() => store.progress(id)?['answers'] as List<Object?>;

  /// Answers questions 1 to 4 with [picks] and moves on to question 5.
  Future<void> playFirstFour(WidgetTester tester, List<String> picks) async {
    for (var q = 0; q < 4; q++) {
      await tapText(tester, picks[q]);
      await pumpUntil(tester, () => savedAnswers()[q] != null, reason: 'answer ${q + 1} saved');
      await tapText(tester, 'Next question');
    }
    expect(find.text('Question 5 of 5 · Medium'), findsOneWidget);
  }

  testWidgets('answering a question marks the options, explains, and saves progress', (tester) async {
    await tester.runAsync(() async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.text('Question 1 of 5 · Medium'), findsOneWidget);
      expect(find.text(prompts[0]), findsOneWidget);
      expect(find.bySemanticsLabel('Question 1, current'), findsOneWidget);
      expect(find.bySemanticsLabel('Question 2, to come'), findsOneWidget);
      expect(find.text('Next question'), findsNothing);

      await tapText(tester, '1,800 kg');
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text(explanations[0]), findsOneWidget);
      expect(find.text('Read the story'), findsOneWidget);
      expect(find.text('A story about whale · The Paper'), findsOneWidget);
      expect(find.text('✓'), findsWidgets);
      expect(find.text('✗'), findsWidgets);
      expect(find.bySemanticsLabel('B. 180 kg, right answer'), findsOneWidget);
      expect(find.bySemanticsLabel('C. 1,800 kg, your answer, wrong'), findsOneWidget);
      expect(find.bySemanticsLabel('Question 1, wrong'), findsOneWidget);
      await pumpUntil(tester, () => store.progress(id) != null, reason: 'progress saved');
      expect(store.progress(id), {
        'answers': [2, null, null, null, null],
        'staked': false,
      });
      expect(store.result(id), isNull);

      await tapText(tester, '18 kg');
      expect(savedAnswers(), [2, null, null, null, null], reason: 'an answered question does not change');

      await tapText(tester, 'Next question');
      expect(find.text('Question 2 of 5 · Medium'), findsOneWidget);
      expect(find.text(prompts[1]), findsOneWidget);
      expect(find.text('Next question'), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('a full run with a stake saves the result once and shows the score', (tester) async {
    await tester.runAsync(() async {
      var completions = 0;
      await pumpScreen(tester, onCompleted: (_) => completions++);
      await playFirstFour(tester, [for (var q = 0; q < 4; q++) right(q)]);

      expect(find.text('WAGER'), findsOneWidget);
      expect(find.text('Stake 1 point? Correct scores 2, wrong loses 1. You have 4 points.'), findsOneWidget);
      await tapText(tester, 'Stake');
      await pumpUntil(tester, () => store.progress(id)?['staked'] == true, reason: 'stake saved');
      await tapText(tester, 'Keep');
      await pumpUntil(tester, () => store.progress(id)?['staked'] == false, reason: 'stake withdrawn');
      await tapText(tester, 'Stake');
      await pumpUntil(tester, () => store.progress(id)?['staked'] == true, reason: 'stake saved again');

      await tapText(tester, 'Pacific');
      expect(find.text('Right'), findsOneWidget);
      expect(find.text('Your stake paid off: two points for this one.'), findsOneWidget);
      expect(find.text('WAGER'), findsNothing);
      expect(find.text('Read the story'), findsNothing, reason: 'no story for this question');
      expect(find.text('See your score'), findsOneWidget);
      await pumpUntil(tester, () => savedAnswers()[4] == 2, reason: 'last answer saved');
      expect(store.result(id), isNull);

      await tapText(tester, 'See your score');
      await pumpUntil(tester, () => store.result(id) != null && !store.hasProgress(id), reason: 'result saved');
      await pumpUntil(tester, () => find.text('Full marks').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.solved, isTrue);
      expect(result.points, 6);
      expect(result.maxPoints, 6);
      expect(result.shareLines, ['🟩🟩🟩🟩⭐🟩']);
      expect(result.isArchivePlay, isFalse);
      expect(completions, 1);
      expect(find.text('6/6'), findsOneWidget);
      expect(find.text('The answers'), findsOneWidget);
      expect(find.text('1. ${prompts[0]}'), findsOneWidget);
      expect(find.text('180 kg'), findsOneWidget);
    });
  });

  testWidgets('a wrong staked answer loses the point', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await playFirstFour(tester, [right(0), wrong(1), right(2), wrong(3)]);
      expect(find.text('Stake 1 point? Correct scores 2, wrong loses 1. You have 2 points.'), findsOneWidget);
      await tapText(tester, 'Stake');
      await pumpUntil(tester, () => store.progress(id)?['staked'] == true, reason: 'stake saved');

      await tapText(tester, 'Arctic');
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('That cost you the point you staked.'), findsOneWidget);
      await tapText(tester, 'See your score');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      await pumpUntil(tester, () => find.text('Tomorrow, then').evaluate().isNotEmpty, reason: 'result screen shown');
      await tester.pumpAndSettle();

      final result = store.result(id)!;
      expect(result.points, 1);
      expect(result.shareLines, ['🟩🟥🟩🟥⭐🟥']);
      expect(find.text('1/6'), findsOneWidget);
    });
  });

  testWidgets('the wager is not offered without a point in hand', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(tester);
      await playFirstFour(tester, [for (var q = 0; q < 4; q++) wrong(q)]);
      expect(find.text('WAGER'), findsNothing);
      expect(find.text('Stake'), findsNothing);
      await tapText(tester, 'Pacific');
      await tapText(tester, 'See your score');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      expect(store.result(id)!.points, 1);
      expect(store.result(id)!.shareLines, ['🟥🟥🟥🟥🟩']);
    });
  });

  testWidgets('saved progress reopens at the next question, and a finished run at the score button', (tester) async {
    await tester.runAsync(() async {
      await store.saveProgress(id, {
        'answers': [1, 2, null, null, null],
        'staked': false,
      });
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.text('Question 3 of 5 · Medium'), findsOneWidget);
      expect(find.bySemanticsLabel('Question 1, right'), findsOneWidget);
      expect(find.bySemanticsLabel('Question 2, wrong'), findsOneWidget);
      expect(find.bySemanticsLabel('Question 3, current'), findsOneWidget);
      semantics.dispose();

      await store.saveProgress(id, {
        'answers': [1, 2, 1, 1, 0],
        'staked': true,
      });
      await pumpScreen(tester);
      expect(find.text('Question 5 of 5 · Medium'), findsOneWidget);
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('See your score'), findsOneWidget);
      await tapText(tester, 'See your score');
      await pumpUntil(tester, () => store.result(id) != null, reason: 'result saved');
      expect(store.result(id)!.points, 2);
      expect(store.result(id)!.shareLines, ['🟩🟥🟩🟩⭐🟥']);
    });
  });

  testWidgets('a completed puzzle reopens read-only with See result', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(
        GameResult(
          puzzleId: id,
          completedAt: DateTime.utc(2026, 9, 8),
          solved: true,
          points: 4,
          maxPoints: 6,
          shareLines: const ['🟩🟥🟩🟩⭐🟥'],
        ),
      );
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, height: 3600);
      for (final p in prompts) {
        expect(find.text(p), findsOneWidget);
      }
      expect(find.text('4/6'), findsOneWidget);
      expect(find.text('Right'), findsNWidgets(3));
      expect(find.text('Not quite'), findsNWidgets(2));
      expect(find.text('Read the story'), findsNWidgets(4));
      expect(find.text('Next question'), findsNothing);
      expect(find.text('See your score'), findsNothing);
      expect(find.text('WAGER'), findsNothing);
      expect(find.bySemanticsLabel('B. 180 kg, right answer'), findsOneWidget);
      expect(find.bySemanticsLabel('Question 2, wrong'), findsOneWidget);
      expect(find.text('⭐'), findsOneWidget);
      semantics.dispose();

      await tapText(tester, '18 kg');
      expect(store.hasProgress(id), isFalse);

      await tapText(tester, 'See result');
      expect(find.text('Well read'), findsOneWidget);
      expect(find.text('The answers'), findsOneWidget);
    });
  });

  testWidgets('a challenge summary is shown above the questions', (tester) async {
    await tester.runAsync(() async {
      await pumpScreen(
        tester,
        challenge: GameResult(puzzleId: id, completedAt: DateTime.utc(2026), solved: true, points: 4, maxPoints: 6),
      );
      expect(find.text('Friend: 4/6'), findsOneWidget);
      expect(QuizScreen.help.paragraphs, hasLength(3));
    });
  });
}
