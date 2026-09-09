import 'dart:math';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/binary/binary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same seed always gives the same puzzle', () {
    final a = BinaryGenerator.generatePuzzle(seed: 20260910);
    final b = BinaryGenerator.generatePuzzle(seed: 20260910);
    expect(a.givens, b.givens);
    expect(a.solution, b.solution);
    final ra = BinaryGenerator().generate(DateTime.utc(2026, 9, 10));
    final rb = BinaryGenerator().generate(DateTime.utc(2026, 9, 10));
    expect(ra, rb);
  });

  test('different seeds give different puzzles', () {
    final a = BinaryGenerator.generatePuzzle(seed: 1);
    final b = BinaryGenerator.generatePuzzle(seed: 2);
    expect(a.givens, isNot(equals(b.givens)));
  });

  test('every seed yields a valid, unique, fair, non-trivial 8×8', () {
    for (var seed = 100; seed < 112; seed++) {
      final puzzle = BinaryGenerator.generatePuzzle(seed: seed);
      final reason = 'seed $seed';
      expect(puzzle.size, 8, reason: reason);
      expect(BinaryRules.isValidSolution(puzzle.solution, 8), isTrue, reason: reason);
      expect(BinarySolver.countSolutions(puzzle.givens, 8), 1, reason: reason);
      expect(BinarySolver.solve(puzzle.givens, 8), puzzle.solution, reason: reason);
      expect(BinarySolver.solvesByPropagation(puzzle.givens, 8), isTrue, reason: reason);
      expect(BinarySolver.solvesByPropagation(puzzle.givens, 8, basicOnly: true), isFalse, reason: reason);
      expect(BinaryGenerator.cellsBeyondBasic(puzzle.givens, 8), greaterThanOrEqualTo(BinaryGenerator.minCellsBeyondBasic));
      expect(puzzle.givenCount, inInclusiveRange(BinaryGenerator.minGivensFor(8), BinaryGenerator.maxGivensFor(8)));
      for (var i = 0; i < 64; i++) {
        if (puzzle.isGiven(i)) expect(puzzle.givens[i], puzzle.solution[i], reason: '$reason cell $i');
      }
    }
  });

  test('other even sizes work', () {
    for (final size in [4, 6, 10]) {
      final puzzle = BinaryGenerator.generatePuzzle(seed: 7, size: size, minGivens: size, maxGivens: size * size ~/ 2);
      expect(puzzle.size, size);
      expect(BinarySolver.countSolutions(puzzle.givens, size), 1);
    }
  });

  test('generate builds a record for the date that re-parses', () {
    final record = BinaryGenerator().generate(DateTime.utc(2026, 10, 3));
    expect(record.id.toString(), 'binary-2026-10-03-en-v1');
    expect(record.game, GameKind.binary);
    expect(record.locale, 'en-GB');
    expect(record.contentVersion, 1);
    expect(record.scoringVersion, 1);
    expect(record.payload['size'], 8);
    expect((record.payload['givens'] as String).length, 64);
    final puzzle = BinaryPuzzle.parse(record.payload, record.reveal);
    expect(puzzle.givenCount, inInclusiveRange(26, 34));
  });

  test('fillGrid produces a valid grid and carve keeps propagation solvability', () {
    final random = Random(7);
    final grid = BinaryGenerator.fillGrid(random, 8);
    expect(BinaryRules.isValidSolution(grid, 8), isTrue);
    final givens = BinaryGenerator.carve(grid, random, 8, target: 30);
    expect(givens.where((g) => g != BinaryRules.empty).length, 30);
    expect(BinarySolver.solvesByPropagation(givens, 8), isTrue);
    expect(BinarySolver.solve(givens, 8), grid);
  });

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(BinaryGenerator.fnv1a(''), 0x811C9DC5);
    expect(BinaryGenerator.fnv1a('a'), 0xE40C292C);
    expect(BinaryGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(BinaryGenerator.seedFor('2026-09-10'), BinaryGenerator.fnv1a('binary-2026-09-10'));
  });
}
