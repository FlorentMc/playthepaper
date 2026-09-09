import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/nonogram/nonogram.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final generator = NonogramGenerator();
  final dates = List.generate(20, (i) => DateTime.utc(2026, 9, 10).add(Duration(days: i)));

  test('fnv1a matches the tool implementation', () {
    expect(NonogramGenerator.fnv1a(''), 0x811C9DC5);
    expect(NonogramGenerator.fnv1a('nonogram-2026-09-10'), 0xB4BE82D9);
    expect(NonogramGenerator.seedFor(DateTime.utc(2026, 9, 10)), NonogramGenerator.fnv1a('nonogram-2026-09-10'));
  });

  test('the picture set holds enough of each size', () {
    expect(generator.passing(NonogramGenerator.smallSize).length, greaterThanOrEqualTo(24));
    expect(generator.passing(NonogramGenerator.largeSize).length, greaterThanOrEqualTo(24));
  });

  test('every authored picture passes the published checks', () {
    for (final picture in nonogramPictures) {
      expect(
        NonogramGenerator.problem(picture),
        isNull,
        reason: '${picture.size}×${picture.size} "${picture.title}"',
      );
    }
  });

  test('the embedded picture set matches content_src/nonogram/pictures.json', () {
    final file = File('content_src/nonogram/pictures.json');
    expect(file.existsSync(), isTrue, reason: 'run tests from the project root');
    final raw = jsonDecode(file.readAsStringSync()) as List;
    final authored = raw.map((p) => NonogramPicture.fromJson(Map<String, dynamic>.from(p as Map))).toList();
    expect(authored.length, nonogramPictures.length);
    for (var i = 0; i < authored.length; i++) {
      expect(authored[i].title, nonogramPictures[i].title, reason: 'picture $i');
      expect(authored[i].rows, nonogramPictures[i].rows, reason: 'picture $i "${authored[i].title}"');
    }
  });

  test('the size alternates with the date', () {
    expect(NonogramGenerator.sizeFor(DateTime.utc(2026, 9, 11)), 5);
    expect(NonogramGenerator.sizeFor(DateTime.utc(2026, 9, 10)), 10);
  });

  test('the same date always gives the same puzzle', () {
    for (final date in dates) {
      final a = NonogramGenerator().generate(date);
      final b = NonogramGenerator().generate(date);
      expect(a.id, b.id);
      expect(a.payload, b.payload);
      expect(a.reveal, b.reveal);
    }
  });

  test('every generated record is a valid, unique, line-solvable nonogram', () {
    for (final date in dates) {
      final record = generator.generate(date);
      final reason = record.id.toString();
      expect(record.id.game, GameKind.nonogram);
      expect(record.locale, 'en-GB');
      expect(record.contentVersion, 1);
      expect(record.scoringVersion, 1);
      final puzzle = NonogramPuzzle.parse(record.payload, record.reveal);
      expect(puzzle.width, NonogramGenerator.sizeFor(date), reason: reason);
      expect(puzzle.height, puzzle.width, reason: reason);
      expect(puzzle.title, isNotEmpty, reason: reason);
      final analysis = NonogramSolver.analyse(puzzle);
      expect(analysis.isUnique, isTrue, reason: reason);
      expect(analysis.lineSolvable, isTrue, reason: reason);
      expect(analysis.sweeps, greaterThanOrEqualTo(NonogramGenerator.minSweeps), reason: '$reason is trivial');
      expect(puzzle.fillFraction, inInclusiveRange(NonogramGenerator.minFill, NonogramGenerator.maxFill), reason: reason);
    }
  });

  test('the rotation runs through every picture of a size before repeating', () {
    for (final size in [NonogramGenerator.smallSize, NonogramGenerator.largeSize]) {
      final pool = generator.passing(size).length;
      final seen = <String>[];
      var date = DateTime.utc(2026, 1, 1);
      while (seen.length < pool) {
        if (NonogramGenerator.sizeFor(date) == size) seen.add(generator.pictureFor(date).title);
        date = date.add(const Duration(days: 1));
      }
      expect(seen.toSet().length, pool, reason: '$size×$size repeats within one turn of the rotation');
    }
  });

  test('the rotation is a permutation of the passing pictures', () {
    for (final size in [NonogramGenerator.smallSize, NonogramGenerator.largeSize]) {
      final order = generator.order(size);
      expect(order.map((p) => p.title).toSet(), generator.passing(size).map((p) => p.title).toSet());
    }
  });

  test('dates before the epoch still rotate without repeating', () {
    final titles = <String>[];
    for (var d = DateTime.utc(2025, 12, 1); d.isBefore(DateTime.utc(2025, 12, 21)); d = d.add(const Duration(days: 1))) {
      if (NonogramGenerator.sizeFor(d) == NonogramGenerator.smallSize) titles.add(generator.pictureFor(d).title);
    }
    expect(titles.toSet().length, titles.length);
  });

  test('problem names why a picture is rejected', () {
    expect(NonogramGenerator.problem(const NonogramPicture(title: 'Odd', rows: ['111', '111', '111'])), contains('size'));
    expect(
      NonogramGenerator.problem(const NonogramPicture(title: 'Ragged', rows: ['1111', '11111', '11111', '11111', '11111'])),
      contains('wide'),
    );
    expect(
      NonogramGenerator.problem(const NonogramPicture(title: 'Empty', rows: ['00000', '00000', '00000', '00000', '00000'])),
      contains('fill'),
    );
    expect(
      NonogramGenerator.problem(const NonogramPicture(title: 'Full', rows: ['11111', '11111', '11111', '11111', '11111'])),
      contains('fill'),
    );
    expect(
      NonogramGenerator.problem(const NonogramPicture(title: 'Ambiguous', rows: ['10010', '00000', '01001', '00100', '00100'])),
      contains('solution'),
    );
  });

  test('generation of 30 dates stays well inside the budget', () {
    final clock = Stopwatch()..start();
    final fresh = NonogramGenerator();
    for (var i = 0; i < 30; i++) {
      fresh.generate(DateTime.utc(2026, 9, 10).add(Duration(days: i)));
    }
    expect(clock.elapsed, lessThan(const Duration(seconds: 60)), reason: '30 dates took ${clock.elapsedMilliseconds}ms');
  });
}
