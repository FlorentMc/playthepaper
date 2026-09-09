import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/app.dart';
import 'package:playthepaper/content/content_repository.dart';
import 'package:playthepaper/core/edition_clock.dart';
import 'package:playthepaper/storage/local_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

String edition(String date) => jsonEncode({
      'date': date,
      'kind': 'evergreen',
      'label': 'Evergreen · Science',
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
        for (final g in ['a', 'b', 'c'])
          {
            'id': 's-$g',
            'headline': 'H $g',
            'summary': 'S',
            'publisher': 'P',
            'url': 'https://example.org',
            'publishedAt': 'evergreen',
          },
      ],
    });

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_home');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  testWidgets('home shows today\'s edition from the bundle when offline', (tester) async {
    final today = EditionClock.formatDate(const EditionClock().today());
    final repo = ContentRepository(
      store: store,
      bundle: FakeBundle({
        'assets/content/index.json': '{"dates": ["$today"], "latest": "$today"}',
        'assets/content/editions/$today.json': edition(today),
      }),
      client: MockClient((_) async => http.Response('down', 503)),
    )..networkEnabled = false;

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PaperApp(store: store, repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Play the Paper'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('EVERGREEN EDITION'), findsOneWidget);
    expect(find.text('Mini Crossword'), findsOneWidget);
    expect(find.text('Sudoku'), findsOneWidget);
    expect(find.text('Easy'), findsOneWidget);
    expect(find.text('Hard'), findsOneWidget);
  });

  testWidgets('home explains when nothing can be loaded', (tester) async {
    final repo = ContentRepository(
      store: store,
      bundle: FakeBundle({}),
      client: MockClient((_) async => http.Response('down', 503)),
    )..networkEnabled = false;
    await tester.pumpWidget(PaperApp(store: store, repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('No edition could be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
