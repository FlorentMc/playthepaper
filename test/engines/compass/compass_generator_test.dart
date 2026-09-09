import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/compass/compass_engine.dart';
import 'package:playthepaper/engines/compass/compass_generator.dart';
import 'package:test/test.dart';

void main() {
  const ranksDir = 'content_src/compass/ranks';
  final files = Directory(ranksDir).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('a prepared rank file ranks 1..N once each and never the target', () {
    expect(files, isNotEmpty, reason: 'run tool/compass_prepare.py first');
    final json = jsonDecode(files.first.readAsStringSync()) as Map<String, dynamic>;
    final target = json['target'] as String;
    final size = json['vocabularySize'] as int;
    final ranks = (json['ranks'] as Map).cast<String, int>();
    expect(RegExp(r'^[a-z]+$').hasMatch(target), isTrue);
    expect(ranks.containsKey(target), isFalse);
    expect(ranks.length, size);
    expect(ranks.values.toSet(), {for (var i = 1; i <= size; i++) i});
    expect(ranks.values.first, 1, reason: 'entries are written nearest first');
    final similarity = (json['similarity'] as List).cast<num>();
    expect(similarity.length, size);
    for (var i = 1; i < similarity.length; i++) {
      expect(similarity[i], lessThanOrEqualTo(similarity[i - 1]), reason: 'similarity falls with rank');
    }
    expect(json['licence'], contains('GloVe'));
    expect(json['licence'], contains('Public Domain Dedication'));
    expect(files.first.lengthSync(), lessThan(120 * 1024));
  });

  test('every prepared rank file parses with the engine', () {
    for (final file in files) {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final puzzle = CompassPuzzle.parse(
        {'vocabularySize': json['vocabularySize']},
        {'target': json['target'], 'ranks': json['ranks']},
      );
      expect(puzzle.wordAt(1), (json['ranks'] as Map).keys.first, reason: file.path);
    }
  });

  test('generate wraps the prepared file in a record the engine accepts', () {
    final name = files.first.uri.pathSegments.last;
    final date = DateTime.parse('${name.substring(0, 10)}T00:00:00Z');
    final record = CompassGenerator().generate(date);
    expect(record.id.game, GameKind.compass);
    expect(record.id.toString(), 'compass-${name.substring(0, 10)}-en-v1');
    expect(record.dictionaryVersion, CompassGenerator.dictionaryVersion);
    expect(record.payload['vocabularySize'], 5000);
    expect(record.payload['attribution'], contains('GloVe'));
    final puzzle = CompassPuzzle.parse(record.payload, record.reveal);
    expect(puzzle.ranks.length, 5000);
    expect(puzzle.ranks.containsKey(puzzle.target), isFalse);
    final pretty = const JsonEncoder.withIndent('  ').convert(record.toJson());
    expect(utf8.encode(pretty).length, lessThanOrEqualTo(CompassGenerator.maxRecordBytes));
    expect(record.reveal.containsKey('similarity'), isFalse, reason: 'similarity is dropped to stay under 120 KB');
  });

  test('generate throws a clear StateError when no file was prepared', () {
    expect(
      () => CompassGenerator().generate(DateTime.utc(1999, 1, 1)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('1999-01-01'))),
    );
    expect(
      () => CompassGenerator(ranksDir: 'content_src/compass/nowhere').generate(DateTime.utc(2026, 9, 10)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('compass_prepare.py'))),
    );
  });
}
