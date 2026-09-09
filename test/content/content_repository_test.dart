import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/content/content_repository.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/puzzle_id.dart';
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

String puzzleJson(String id, String game) => jsonEncode({
      'id': id,
      'game': game,
      'editionDate': id.split('-').sublist(1, 4).join('-'),
      'locale': 'en-GB',
      'contentVersion': 1,
      'scoringVersion': 1,
      'payload': {'x': 1},
      'reveal': {'y': 2},
    });

String editionJson(String date, {String kind = 'evergreen', String label = 'Evergreen'}) => jsonEncode({
      'date': date,
      'kind': kind,
      'label': label,
      'version': 1,
      'puzzles': ['word-$date-en-v1'],
      'stories': [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('playthepaper_test');
    store = await LocalStore.open(subDir: dir.path);
  });

  tearDown(() async {
    await store.clearAll();
    await dir.delete(recursive: true);
  });

  ContentRepository repo({Map<String, String>? assets, Map<String, String>? remote}) {
    final bundle = FakeBundle({
      for (final e in (assets ?? {}).entries) 'assets/content/${e.key}': e.value,
    });
    final client = MockClient((request) async {
      final path = request.url.path.replaceFirst('/content/', '');
      final body = remote?[path];
      if (body == null) return http.Response('not found', 404);
      return http.Response(body, 200);
    });
    return ContentRepository(store: store, bundle: bundle, client: client, baseUrl: 'https://example.test/content');
  }

  test('bundled puzzle loads without network', () async {
    final r = repo(assets: {'puzzles/word-2026-09-08-en-v1.json': puzzleJson('word-2026-09-08-en-v1', 'word')});
    final p = await r.puzzle(PuzzleId.parse('word-2026-09-08-en-v1'));
    expect(p.payload['x'], 1);
  });

  test('network puzzle is cached for next time', () async {
    final r = repo(remote: {'puzzles/word-2026-09-08-en-v1.json': puzzleJson('word-2026-09-08-en-v1', 'word')});
    final id = PuzzleId.parse('word-2026-09-08-en-v1');
    await r.puzzle(id);
    final offline = repo(); // no assets, no remote
    final p = await offline.puzzle(id);
    expect(p.id, id);
  });

  test('missing puzzle throws ContentNotFound', () async {
    expect(() => repo().puzzle(PuzzleId.parse('word-2026-09-08-en-v1')), throwsA(isA<ContentNotFound>()));
  });

  test("today's edition prefers the network so news can replace evergreen", () async {
    final r = repo(
      assets: {'editions/2026-09-08.json': editionJson('2026-09-08')},
      remote: {'editions/2026-09-08.json': editionJson('2026-09-08', kind: 'news', label: 'Today')},
    );
    final m = await r.edition(DateTime.utc(2026, 9, 8), preferNetwork: true);
    expect(m.kind, EditionKind.news);
    // And it is now cached, so an offline load keeps the news edition.
    final m2 = await repo(assets: {'editions/2026-09-08.json': editionJson('2026-09-08')}).edition(DateTime.utc(2026, 9, 8));
    expect(m2.kind, EditionKind.news);
  });

  test('older editions use bundle when network is down', () async {
    final r = repo(assets: {'editions/2026-09-01.json': editionJson('2026-09-01')});
    final m = await r.edition(DateTime.utc(2026, 9, 1));
    expect(m.label, 'Evergreen');
  });

  test('a corrupt remote file never replaces a good bundled one', () async {
    final r = repo(
      assets: {'editions/2026-09-08.json': editionJson('2026-09-08')},
      remote: {'editions/2026-09-08.json': '{"date": "2026-09-08"}'},
    );
    final m = await r.edition(DateTime.utc(2026, 9, 8), preferNetwork: true);
    expect(m.label, 'Evergreen');
  });

  test('a puzzle file whose id does not match its name is rejected', () async {
    final r = repo(assets: {'puzzles/word-2026-09-08-en-v1.json': puzzleJson('word-2026-09-09-en-v1', 'word')});
    expect(() => r.puzzle(PuzzleId.parse('word-2026-09-08-en-v1')), throwsA(isA<ContentNotFound>()));
  });

  test('index merges bundle, network and cache', () async {
    final r = repo(
      assets: {'index.json': '{"dates": ["2026-09-01"], "latest": "2026-09-01"}'},
      remote: {
        'index.json': '{"dates": ["2026-09-01", "2026-09-02"], "latest": "2026-09-02"}',
        'editions/2026-09-05.json': editionJson('2026-09-05'),
      },
    );
    await r.edition(DateTime.utc(2026, 9, 5));
    final idx = await r.index();
    expect(idx.dates, [DateTime.utc(2026, 9, 1), DateTime.utc(2026, 9, 2), DateTime.utc(2026, 9, 5)]);
    expect(idx.latest, DateTime.utc(2026, 9, 2));
  });
}
