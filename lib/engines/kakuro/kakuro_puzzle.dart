import 'kakuro_grid.dart';
import 'kakuro_solver.dart';

/// A validated puzzle: the grid and its unique solution.
///
/// Payload: `{"width": 6, "height": 6, "cells": ["#", {"down": 16, "across": null}, ".", ...]}`.
/// Reveal: `{"solution": ["#", "#", "7", ...]}`, a digit string for every
/// white cell and `"#"` for every other cell.
class KakuroPuzzle {
  /// Validates and copies [solution] against [grid]. Throws [FormatException]
  /// when the solution has the wrong shape, breaks a rule (an empty white
  /// cell, a repeated digit in a run, a run with the wrong sum), or is not
  /// the grid's only solution.
  factory KakuroPuzzle({required KakuroGrid grid, required List<int> solution}) {
    if (solution.length != grid.cellCount) {
      throw FormatException('Kakuro solution must have ${grid.cellCount} cells, got ${solution.length}');
    }
    for (var i = 0; i < grid.cellCount; i++) {
      if (!grid.isWhite(i) && solution[i] != 0) {
        throw FormatException('Kakuro solution has a digit at index $i, which is not a white cell');
      }
    }
    final violation = grid.firstViolation(solution);
    if (violation != null) throw FormatException(violation);
    if (KakuroSolver.countSolutions(grid) != 1) {
      throw const FormatException('Kakuro clues do not have a unique solution');
    }
    return KakuroPuzzle._(grid, List<int>.unmodifiable(solution));
  }

  const KakuroPuzzle._(this.grid, this.solution);

  static KakuroPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final grid = KakuroGrid.parsePayload(payload);
    final raw = reveal['solution'];
    if (raw is! List) throw const FormatException('Kakuro reveal is missing "solution"');
    if (raw.length != grid.cellCount) {
      throw FormatException('Kakuro solution must have ${grid.cellCount} cells, got ${raw.length}');
    }
    final solution = List<int>.filled(grid.cellCount, 0);
    for (var i = 0; i < grid.cellCount; i++) {
      final v = raw[i];
      if (grid.isWhite(i)) {
        if (v is! String || v.length != 1 || v.codeUnitAt(0) < 0x31 || v.codeUnitAt(0) > 0x39) {
          throw FormatException('Kakuro solution at index $i must be a digit from 1 to 9');
        }
        solution[i] = v.codeUnitAt(0) - 0x30;
      } else if (v != '#') {
        throw FormatException('Kakuro solution at index $i must be "#" for a cell that is not white');
      }
    }
    return KakuroPuzzle(grid: grid, solution: solution);
  }

  final KakuroGrid grid;

  /// One value per cell: the digit for white cells, 0 elsewhere.
  final List<int> solution;

  int get width => grid.width;
  int get height => grid.height;
  List<KakuroCell> get cells => grid.cells;
  List<KakuroRun> get runs => grid.runs;
  List<int> get whiteCells => grid.whiteCells;

  Map<String, dynamic> toPayload() => grid.toPayload();

  Map<String, dynamic> toReveal() => {
        'solution': [for (var i = 0; i < grid.cellCount; i++) grid.isWhite(i) ? '${solution[i]}' : '#'],
      };
}
