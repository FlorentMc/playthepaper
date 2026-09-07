import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/engines/sudoku/sudoku.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('a singles-only puzzle is easy', () {
    final grade = SudokuGrader.grade(cells(singlesOnlyGivens));
    expect(grade.solved, isTrue);
    expect(grade.difficulty, Difficulty.easy);
    expect(grade.techniques, isNotEmpty);
    expect(grade.techniques.every((t) => t.isSingle), isTrue);
  });

  test('a solved grid is easy with no techniques', () {
    final grade = SudokuGrader.grade(cells(singlesOnlySolution, allowBlank: false));
    expect(grade.solved, isTrue);
    expect(grade.difficulty, Difficulty.easy);
    expect(grade.techniques, isEmpty);
  });

  test('a puzzle needing a naked pair is medium', () {
    final grade = SudokuGrader.grade(cells(nakedPairGivens));
    expect(grade.solved, isTrue);
    expect(grade.difficulty, Difficulty.medium);
    expect(grade.techniques, contains(SudokuTechnique.nakedPair));
  });

  test('a puzzle needing a hidden pair is medium', () {
    final grade = SudokuGrader.grade(cells(hiddenPairGivens));
    expect(grade.solved, isTrue);
    expect(grade.difficulty, Difficulty.medium);
    expect(grade.techniques, contains(SudokuTechnique.hiddenPair));
  });

  test('a puzzle beyond pairs and box-line logic is hard', () {
    final grade = SudokuGrader.grade(cells(xWingGivens));
    expect(grade.solved, isFalse);
    expect(grade.difficulty, Difficulty.hard);
  });

  test('a grid with no unique solution is not reported as solved', () {
    final grade = SudokuGrader.grade(twoSolutionGrid(cells(singlesOnlySolution, allowBlank: false)));
    expect(grade.solved, isFalse);
    expect(grade.difficulty, Difficulty.hard);
  });

  test('generated puzzles grade as requested and use the expected techniques', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 5; seed++) {
        final puzzle = SudokuGenerator.generate(seed: seed, difficulty: difficulty);
        final grade = SudokuGrader.grade(puzzle.givens);
        expect(grade.difficulty, difficulty, reason: '${difficulty.slug} seed $seed');
        switch (difficulty) {
          case Difficulty.easy:
            expect(grade.solved, isTrue);
            expect(grade.techniques.every((t) => t.isSingle), isTrue);
          case Difficulty.medium:
            expect(grade.solved, isTrue);
            expect(grade.techniques.any((t) => !t.isSingle), isTrue);
          case Difficulty.hard:
            expect(grade.solved, isFalse);
        }
      }
    }
  });
}
