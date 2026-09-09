import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/tangram/tangram.dart';

void main() {
  final generator = TangramGenerator();

  group('the authored figures', () {
    test('there are at least forty and every one passes the checks', () {
      expect(tangramSilhouettes.length, greaterThanOrEqualTo(40));
      for (final silhouette in tangramSilhouettes) {
        expect(TangramGenerator.problem(silhouette), isNull, reason: silhouette.name);
      }
      expect(generator.passing, hasLength(tangramSilhouettes.length));
    });

    test('names and figures are all different', () {
      final names = <String>{}, masks = <String>{};
      for (final silhouette in tangramSilhouettes) {
        expect(names.add(silhouette.name), isTrue, reason: silhouette.name);
        expect(masks.add(silhouette.centred().toPuzzle().mask.rows.join()), isTrue,
            reason: silhouette.name);
      }
    });

    test('each one is made by the seven pieces it names', () {
      for (final silhouette in tangramSilhouettes) {
        final puzzle = silhouette.centred().toPuzzle();
        final check = TangramChecker.check(puzzle.mask, puzzle.solution);
        expect(check.isComplete, isTrue, reason: silhouette.name);
        expect(puzzle.outline, hasLength(1), reason: silhouette.name);
        expect(puzzle.mask.filled, greaterThan(200), reason: silhouette.name);
      }
    });

    test('every figure sits in the middle of the board', () {
      for (final silhouette in tangramSilhouettes) {
        final bounds = silhouette.centred().toPuzzle().bounds;
        expect(bounds.left, greaterThanOrEqualTo(0), reason: silhouette.name);
        expect(bounds.right, lessThanOrEqualTo(TangramGeometry.boardUnits), reason: silhouette.name);
        expect((bounds.left - (TangramGeometry.boardUnits - bounds.right)).abs(), lessThanOrEqualTo(1),
            reason: silhouette.name);
      }
    });

    test('the engine copy matches content_src/tangram/silhouettes.json', () {
      final file = File('content_src/tangram/silhouettes.json');
      expect(file.existsSync(), isTrue);
      final raw = jsonDecode(file.readAsStringSync()) as List;
      final authored = raw.map((s) => TangramSilhouette.fromJson(Map<String, dynamic>.from(s as Map)));
      expect(
        authored.map((s) => jsonEncode(s.toJson())).toList(),
        tangramSilhouettes.map((s) => jsonEncode(s.toJson())).toList(),
      );
    });

    test('a figure with too few corners or a piece adrift is rejected', () {
      const square = TangramSilhouette(name: 'Square', placements: [
        TangramPlacement(piece: TangramPiece.largeTriangleA, x: 2, y: 3),
        TangramPlacement(piece: TangramPiece.largeTriangleB, x: 1, y: 2, rotation: 2),
        TangramPlacement(piece: TangramPiece.mediumTriangle, x: 3, y: 1, rotation: 4),
        TangramPlacement(piece: TangramPiece.smallTriangleA, x: 4, y: 3, rotation: 6),
        TangramPlacement(piece: TangramPiece.smallTriangleB, x: 2, y: 1, rotation: 4),
        TangramPlacement(piece: TangramPiece.square, x: 3, y: 2),
        TangramPlacement(piece: TangramPiece.parallelogram, x: 2, y: 1, flipped: true),
      ]);
      expect(TangramGenerator.problem(square), contains('too plain'));
      final adrift = TangramSilhouette(
        name: 'Adrift',
        placements: [
          for (final placement in square.placements)
            placement.piece == TangramPiece.square ? placement.movedTo(7, 7) : placement,
        ],
      );
      expect(TangramGenerator.problem(adrift), contains('contours'));
    });
  });

  group('generate', () {
    test('the same date always gives the same puzzle', () {
      final date = DateTime.utc(2026, 9, 10);
      final first = generator.generate(date);
      final second = TangramGenerator().generate(date);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
      expect(first.id.toString(), 'tangram-2026-09-10-en-v1');
    });

    test('every date in a long run parses and is solvable', () {
      final clock = Stopwatch()..start();
      for (var day = 0; day < 30; day++) {
        final date = DateTime.utc(2026, 9, 10).add(Duration(days: day));
        final record = generator.generate(date);
        expect(record.game, GameKind.tangram);
        expect(record.locale, 'en-GB');
        expect(record.contentVersion, 1);
        expect(record.scoringVersion, 1);
        final reparsed = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
        final puzzle = TangramPuzzle.parse(reparsed.payload, reparsed.reveal);
        expect(TangramChecker.check(puzzle.mask, puzzle.solution).isComplete, isTrue);
      }
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'thirty dates should take well under two seconds');
    });

    test('no figure comes round again until every one has been used', () {
      final count = generator.passing.length;
      final seen = <String>{};
      for (var day = 0; day < count; day++) {
        final date = DateTime.utc(2026, 1, 1).add(Duration(days: day));
        expect(seen.add(generator.silhouetteFor(date).name), isTrue);
      }
      expect(seen, hasLength(count));
      expect(
        generator.silhouetteFor(DateTime.utc(2026, 1, 1).add(Duration(days: count))).name,
        isIn(seen),
      );
    });

    test('rounds are dealt in a different order', () {
      final count = generator.passing.length;
      final first = [for (var d = 0; d < count; d++) generator.order(0)[d].name];
      final second = [for (var d = 0; d < count; d++) generator.order(1)[d].name];
      expect(first, isNot(second));
      expect(first.toSet(), second.toSet());
    });

    test('dates before the epoch still work', () {
      expect(TangramGenerator.ordinalFor(DateTime.utc(2025, 12, 31)), -1);
      final record = generator.generate(DateTime.utc(2025, 12, 31));
      expect(TangramPuzzle.parse(record.payload, record.reveal).name, isNotEmpty);
    });

    test('the seed is the same FNV-1a the other tools use', () {
      expect(TangramGenerator.fnv1a('tangram-2026-09-10'), TangramGenerator.seedFor(DateTime.utc(2026, 9, 10)));
      expect(TangramGenerator.fnv1a(''), 0x811C9DC5);
      expect(TangramGenerator.fnv1a('a'), 0xE40C292C);
    });
  });
}
