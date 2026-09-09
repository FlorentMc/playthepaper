import 'binary_rules.dart';
import 'binary_solver.dart';

/// A validated Takuzu puzzle: the givens and their unique solution.
///
/// Payload: `{"size": 8, "givens": "64 chars of 0, 1 or ."}`.
/// Reveal: `{"solution": "64 chars of 0 or 1"}`.
class BinaryPuzzle {
  /// Validates and copies [givens] and [solution]. Throws [FormatException]
  /// when the size is odd or out of range, the solution breaks a rule, the
  /// givens are not a subset of it, or the givens admit more than one
  /// solution.
  factory BinaryPuzzle({required int size, required List<int> givens, required List<int> solution}) {
    BinaryRules.checkSize(size);
    final count = size * size;
    if (givens.length != count || solution.length != count) {
      throw FormatException('Binary givens and solution must have $count cells for size $size');
    }
    if (!BinaryRules.isValidSolution(solution, size)) {
      throw const FormatException('Binary solution breaks a rule');
    }
    for (var i = 0; i < count; i++) {
      final g = givens[i];
      if (g != BinaryRules.empty && g != 0 && g != 1) {
        throw FormatException('Binary given at index $i is out of range: $g');
      }
      if (g != BinaryRules.empty && g != solution[i]) {
        throw FormatException('Binary given at index $i ($g) disagrees with the solution (${solution[i]})');
      }
    }
    if (BinarySolver.countSolutions(givens, size) != 1) {
      throw const FormatException('Binary givens do not have a unique solution');
    }
    return BinaryPuzzle._(size, List<int>.unmodifiable(givens), List<int>.unmodifiable(solution));
  }

  const BinaryPuzzle._(this.size, this.givens, this.solution);

  static BinaryPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawSize = payload['size'];
    if (rawSize is! int) throw const FormatException('Binary payload is missing "size"');
    BinaryRules.checkSize(rawSize);
    final rawGivens = payload['givens'];
    if (rawGivens is! String) throw const FormatException('Binary payload is missing "givens"');
    final rawSolution = reveal['solution'];
    if (rawSolution is! String) throw const FormatException('Binary reveal is missing "solution"');
    return BinaryPuzzle(
      size: rawSize,
      givens: BinaryRules.parseCells(rawGivens, rawSize, field: 'givens', allowBlank: true),
      solution: BinaryRules.parseCells(rawSolution, rawSize, field: 'solution', allowBlank: false),
    );
  }

  final int size;

  /// `size × size` values, [BinaryRules.empty] for a blank cell.
  final List<int> givens;

  /// `size × size` values, 0 or 1.
  final List<int> solution;

  int get cellCount => size * size;

  bool isGiven(int index) => givens[index] != BinaryRules.empty;

  int get givenCount => givens.where((g) => g != BinaryRules.empty).length;

  String get givensString => BinaryRules.formatCells(givens);
  String get solutionString => BinaryRules.formatCells(solution);

  Map<String, dynamic> toPayload() => {'size': size, 'givens': givensString};
  Map<String, dynamic> toReveal() => {'solution': solutionString};
}
