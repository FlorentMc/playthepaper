import 'dart:convert';
import 'dart:math';

import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(KakuroGenerator.fnv1a(''), 0x811C9DC5);
    expect(KakuroGenerator.fnv1a('a'), 0xE40C292C);
    expect(KakuroGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(KakuroGenerator.seedFor('2026-09-10'), KakuroGenerator.fnv1a('kakuro-2026-09-10'));
    expect(KakuroGenerator.seedFor('2026-09-10'), isNot(KakuroGenerator.seedFor('2026-09-11')));
  });

  test('the same date always gives the same record', () {
    final a = KakuroGenerator().generate(DateTime.utc(2026, 9, 10));
    final b = KakuroGenerator().generate(DateTime.utc(2026, 9, 10, 15));
    expect(a, b);
    expect(a.id.toString(), 'kakuro-2026-09-10-en-v1');
    expect(a.game, GameKind.kakuro);
    expect(a.locale, 'en-GB');
    expect(a.contentVersion, 1);
    expect(a.scoringVersion, 1);
    final c = KakuroGenerator().generate(DateTime.utc(2026, 9, 11));
    expect(c.payload, isNot(equals(a.payload)));
  });

  test('records survive a JSON round trip and re-parse', () {
    final record = KakuroGenerator().generate(DateTime.utc(2026, 10, 1));
    final back = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    expect(back, record);
    final puzzle = KakuroPuzzle.parse(back.payload, back.reveal);
    expect(puzzle.toPayload(), record.payload);
    expect(puzzle.toReveal(), record.reveal);
  });

  test('every seed yields a valid 6×6 board of the promised shape', () {
    for (var seed = 100; seed < 112; seed++) {
      final puzzle = KakuroGenerator.generatePuzzle(seed);
      final grid = puzzle.grid;
      final reason = 'seed $seed';
      expect(grid.width, 6, reason: reason);
      expect(grid.height, 6, reason: reason);
      expect(grid.whiteCount, greaterThanOrEqualTo(KakuroGenerator.minWhiteCells), reason: reason);
      for (var i = 0; i < 6; i++) {
        expect(grid.isWhite(i), isFalse, reason: '$reason: top row holds clues');
        expect(grid.isWhite(i * 6), isFalse, reason: '$reason: left column holds clues');
      }
      for (final run in grid.runs) {
        expect(run.length, inInclusiveRange(2, 5), reason: reason);
        expect(grid.cells[run.clueCell].isClue, isTrue, reason: reason);
      }
      for (final w in grid.whiteCells) {
        expect(grid.runs.where((r) => r.cells.contains(w)).length, 2, reason: reason);
      }
      for (var i = 0; i < grid.cellCount; i++) {
        final cell = grid.cells[i];
        if (cell.isClue) expect(cell.down != null || cell.across != null, isTrue, reason: reason);
      }
      expect(grid.firstViolation(puzzle.solution), isNull, reason: reason);
      expect(KakuroSolver.countSolutions(grid), 1, reason: reason);
      expect(KakuroSolver.solve(grid), puzzle.solution, reason: reason);
      expect(KakuroGenerator.isAcceptable(grid), isTrue, reason: reason);
      final deduction = KakuroSolver.deduce(grid);
      expect(deduction.solves(grid), isTrue, reason: '$reason: no guessing needed');
      expect(deduction.rounds, greaterThanOrEqualTo(KakuroGenerator.minRounds), reason: reason);
      expect(KakuroGenerator.firstPassShare(grid), lessThanOrEqualTo(KakuroGenerator.maxFirstPassShare), reason: reason);
    }
  });

  test('layouts keep every white cell in two runs and connected', () {
    for (var seed = 0; seed < 40; seed++) {
      final white = KakuroGenerator.carveLayout(Random(seed));
      if (white == null) continue;
      final count = white.where((w) => w).length;
      expect(count, greaterThanOrEqualTo(KakuroGenerator.minWhiteCells));
      final digits = KakuroGenerator.fillDigits(white, Random(seed))!;
      final grid = KakuroGrid(width: 6, height: 6, cells: KakuroGenerator.clueCells(white, digits));
      expect(grid.whiteCount, count);
      expect(grid.firstViolation(digits), isNull, reason: 'the fill respects the clues it produced');
    }
  });

  test('trivial and ambiguous boards are not acceptable', () {
    final ambiguous = KakuroGrid.parsePayload({
      'width': 3,
      'height': 3,
      'cells': ['#', {'down': 3}, {'down': 3}, {'across': 3}, '.', '.', {'across': 3}, '.', '.'],
    });
    expect(KakuroGenerator.isAcceptable(ambiguous), isFalse);
    final tiny = KakuroGrid.parsePayload({
      'width': 3,
      'height': 3,
      'cells': ['#', {'down': 4}, {'down': 3}, {'across': 3}, '.', '.', {'across': 4}, '.', '.'],
    });
    expect(KakuroSolver.countSolutions(tiny), 1);
    expect(KakuroGenerator.isAcceptable(tiny), isFalse, reason: 'fewer than ${KakuroGenerator.minWhiteCells} cells');
    expect(KakuroGenerator.firstPassShare(tiny), 0.5, reason: 'two cells sit where 3 and 4 cross');
  });
}
