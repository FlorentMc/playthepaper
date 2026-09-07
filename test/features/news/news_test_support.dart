import 'dart:convert';
import 'dart:io';

import 'package:daypencil/content/content_repository.dart';
import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/core/theme.dart';
import 'package:daypencil/features/play/play_context.dart';
import 'package:daypencil/storage/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

final DateTime kTestDate = DateTime.utc(2026, 1, 1);
const String kTestDateText = '2026-01-01';

Map<String, dynamic> evergreenJson(String slug) =>
    jsonDecode(File('content_src/evergreen/$slug.json').readAsStringSync()) as Map<String, dynamic>;

/// A puzzle record for [game] built from an evergreen source file.
PuzzleRecord evergreenRecord(String slug, GameKind game) {
  final json = evergreenJson(slug);
  final puzzle = (json['puzzles'] as Map)[game.slug] as Map;
  return PuzzleRecord.fromJson({
    'id': PuzzleId(game: game, date: kTestDate).toString(),
    'game': game.slug,
    'editionDate': kTestDateText,
    'locale': 'en-GB',
    'contentVersion': 1,
    'scoringVersion': 1,
    'payload': puzzle['payload'],
    'reveal': puzzle['reveal'],
    'storyId': '$slug-${game.slug}',
    'sources': puzzle['sources'],
  });
}

Story evergreenStory(String slug, GameKind game) {
  final json = evergreenJson(slug);
  return (json['stories'] as List)
      .map((s) => Story.fromJson(s as Map<String, dynamic>))
      .firstWhere((s) => s.game == game);
}

/// An edition manifest for the test date built from an evergreen file.
String evergreenEditionJson(String slug) {
  final json = evergreenJson(slug);
  return jsonEncode({
    'date': kTestDateText,
    'kind': 'evergreen',
    'label': json['label'],
    'version': 1,
    'puzzles': [for (final g in GameKind.newsOrder) PuzzleId(game: g, date: kTestDate).toString()],
    'stories': json['stories'],
  });
}

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

/// A fresh store in a temporary directory. The store writes to disk, so
/// test bodies that touch it run under [WidgetTester.runAsync].
Future<LocalStore> openTestStore() async {
  final dir = await Directory.systemTemp.createTemp('daypencil_news');
  return LocalStore.open(subDir: dir.path);
}

/// Lets the store finish writing, then renders what changed.
Future<void> settle(WidgetTester tester) async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// A tall viewport so whole screens are on stage without scrolling.
void useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

PlayContext playFor(LocalStore store, PuzzleRecord record, {Story? story, bool isArchivePlay = false}) =>
    PlayContext(store: store, record: record, story: story, isArchivePlay: isArchivePlay);

/// Wraps [home] the way `lib/app.dart` does: providers, theme and a router.
Widget harness(LocalStore store, Widget home, {ContentRepository? repository}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (c, s) => home),
      GoRoute(path: '/p/:id', builder: (c, s) => Scaffold(body: Text('play ${s.pathParameters['id']}'))),
      GoRoute(path: '/front/:date', builder: (c, s) => Scaffold(body: Text('front ${s.pathParameters['date']}'))),
    ],
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LocalStore>.value(value: store),
      ChangeNotifierProvider<Settings>.value(value: store.settings),
      if (repository != null) Provider<ContentRepository>.value(value: repository),
    ],
    child: MaterialApp.router(
      theme: DaypencilTheme.light(),
      routerConfig: router,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
    ),
  );
}

/// The shell opens the help sheet on a game's first appearance in a session.
Future<void> settleAndDismissHelp(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final gotIt = find.text('Got it');
  if (gotIt.evaluate().isNotEmpty) {
    await tester.tap(gotIt);
    await tester.pumpAndSettle();
  }
}
