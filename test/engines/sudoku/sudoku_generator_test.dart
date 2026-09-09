import 'dart:math';

import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/sudoku/sudoku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same seed and difficulty always give the same puzzle', () {
    for (final difficulty in Difficulty.values) {
      final a = SudokuGenerator.generate(seed: 20260901, difficulty: difficulty);
      final b = SudokuGenerator.generate(seed: 20260901, difficulty: difficulty);
      expect(a.givens, b.givens);
      expect(a.solution, b.solution);
    }
  });

  test('different seeds give different puzzles', () {
    final a = SudokuGenerator.generate(seed: 1, difficulty: Difficulty.easy);
    final b = SudokuGenerator.generate(seed: 2, difficulty: Difficulty.easy);
    expect(a.givens, isNot(equals(b.givens)));
  });

  test('every difficulty yields a valid, symmetric, correctly graded puzzle', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 100; seed < 110; seed++) {
        final puzzle = SudokuGenerator.generate(seed: seed, difficulty: difficulty);
        final reason = '${difficulty.slug} seed $seed';
        expect(SudokuGrid.isValidSolution(puzzle.solution), isTrue, reason: reason);
        expect(SudokuSolver.countSolutions(puzzle.givens), 1, reason: reason);
        expect(SudokuSolver.solve(puzzle.givens), puzzle.solution, reason: reason);
        expect(SudokuGrader.grade(puzzle.givens).difficulty, difficulty, reason: reason);
        for (var i = 0; i < 81; i++) {
          expect(puzzle.givens[i] == 0, puzzle.givens[80 - i] == 0, reason: '$reason symmetry at $i');
        }
        expect(puzzle.givenCount, greaterThanOrEqualTo(SudokuGenerator.minGivens[difficulty]!), reason: reason);
        if (difficulty == Difficulty.easy) expect(puzzle.givenCount, greaterThanOrEqualTo(24), reason: reason);
        if (difficulty == Difficulty.hard) {
          expect(puzzle.givenCount, inInclusiveRange(22, SudokuGenerator.maxHardGivens), reason: reason);
        }
      }
    }
  });

  test('parsing the generated payload and reveal reproduces the puzzle', () {
    final puzzle = SudokuGenerator.generate(seed: 42, difficulty: Difficulty.medium);
    final parsed = SudokuPuzzle.parse(puzzle.toPayload(), puzzle.toReveal());
    expect(parsed.givens, puzzle.givens);
    expect(parsed.solution, puzzle.solution);
  });

  test('fillGrid produces a valid grid and carve keeps uniqueness', () {
    final random = Random(7);
    final grid = SudokuGenerator.fillGrid(random);
    expect(SudokuGrid.isValidSolution(grid), isTrue);
    final givens = SudokuGenerator.carve(grid, random, minGivens: 30);
    expect(SudokuSolver.countSolutions(givens), 1);
    expect(givens.where((g) => g != 0).length, greaterThanOrEqualTo(30));
  });

  test('seeds are a stable FNV-1a hash of the puzzle name', () {
    expect(SudokuGenerator.fnv1a(''), 0x811C9DC5);
    expect(SudokuGenerator.fnv1a('a'), 0xE40C292C);
    expect(SudokuGenerator.fnv1a('foobar'), 0xBF9CF968);
    expect(SudokuGenerator.seedFor('2026-09-01', Difficulty.easy), 0x73CA3462);
    expect(SudokuGenerator.seedFor('2026-09-01', Difficulty.hard), 0xA53606B9);
  });
}
