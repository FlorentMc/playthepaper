import 'dart:convert';
import 'dart:io';

import 'package:daypencil/content/content_repository.dart';
import 'package:daypencil/core/game_result.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/core/theme.dart';
import 'package:daypencil/features/news/front_page_screen.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class FakeBundle extends CachingAssetBundle {
  FakeBundle(this.files);
  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final s = files[key];
    if (s == null) throw StateError('missing $key');
    return ByteData.sublistView(utf8.encode(s));
  }
}

const date = '2026-09-08';

String edition() => jsonEncode({
      'date': date,
      'kind': 'evergreen',
      'label': 'Evergreen · Nature',
      'version': 1,
      'puzzles': [
        'word-$date-en-v1',
        'sudoku-$date-en-easy-v1',
        'sudoku-$date-en-medium-v1',
        'sudoku-$date-en-hard-v1',
        'letters-$date-en-v1',
        'crossword-$date-en-v1',
        'quiz-$date-en-v1',
      ],
      'stories': [
        for (final n in ['a', 'b', 'c'])
          {
            'id': 'story-$n',
            'headline': 'Headline $n',
            'summary': 'Summary $n.',
            'publisher': 'Wikipedia',
            'url': 'https://example.org/$n',
            'publishedAt': 'evergreen',
          },
      ],
      'seeds': {
        'story-a': ['quiz:1', 'quiz:2', 'word'],
        'story-b': ['quiz:3', 'crossword:5 Across'],
        'story-c': ['quiz:4', 'quiz:5', 'letters'],
      },
    });

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('daypencil_front');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    final repo = ContentRepository(
      store: store,
      bundle: FakeBundle({'assets/content/editions/$date.json': edition()}),
      client: MockClient((_) async => http.Response('down', 503)),
    )..networkEnabled = false;
    final editions = EditionController(repository: repo);
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocalStore>.value(value: store),
          ChangeNotifierProvider<Settings>.value(value: store.settings),
          Provider<ContentRepository>.value(value: repo),
          ChangeNotifierProvider<EditionController>.value(value: editions),
        ],
        child: MaterialApp.router(
          theme: DaypencilTheme.light(),
          routerConfig: GoRouter(
            initialLocation: '/front/$date',
            routes: [
              GoRoute(path: '/', builder: (c, s) => const Scaffold(body: Text('home'))),
              GoRoute(path: '/front/:date', builder: (c, s) => FrontPageScreen(dateText: s.pathParameters['date']!)),
              GoRoute(path: '/news/:date', builder: (c, s) => const Scaffold(body: Text('quiz'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('stories stay locked until the quiz is done, and Reveal opens them', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      expect(find.text('Story 1'), findsOneWidget);
      expect(find.text('Headline a'), findsNothing);
      expect(find.text('2 questions · Daily Word'), findsOneWidget);
      await tester.tap(find.text('Reveal'));
      await tester.pumpAndSettle();
      expect(find.text('Headline a'), findsOneWidget);
      expect(find.text('Summary c.'), findsOneWidget);
    });
  });

  testWidgets('after the quiz, stories are open and tagged with results', (tester) async {
    await tester.runAsync(() async {
      await store.saveResult(GameResult(
        puzzleId: PuzzleId.parse('quiz-$date-en-v1'),
        completedAt: DateTime.utc(2026),
        solved: true,
        points: 5,
        maxPoints: 6,
        shareLines: const ['🟩🟥🟩🟩⭐🟩'],
      ));
      await store.saveResult(GameResult(
        puzzleId: PuzzleId.parse('word-$date-en-v1'),
        completedAt: DateTime.utc(2026),
        solved: true,
        attempts: 3,
      ));
      await pump(tester);
      expect(find.text('Headline b'), findsOneWidget);
      expect(find.text('Question 1 🟩'), findsOneWidget);
      expect(find.text('Question 2 🟥'), findsOneWidget);
      expect(find.text('Daily Word · Solved in 3/6'), findsOneWidget);
      expect(find.text('Mini Crossword 5 Across'), findsOneWidget);
      expect(find.text('Share the edition'), findsOneWidget);
    });
  });
}
