import 'regions_grid.dart';
import 'regions_solver.dart';

/// A validated puzzle: the layout, the givens and their unique solution.
///
/// Payload: `{"width": 6, "height": 6, "regions": "36 region letters", "givens": "36 chars, digit or ."}`.
/// Reveal: `{"solution": "36 digits"}`.
class RegionsPuzzle {
  /// Validates [givens] and [solution] on [grid]. Throws [FormatException]
  /// when the solution breaks a rule, a given disagrees with it, or the
  /// givens admit more than one solution.
  factory RegionsPuzzle({required RegionsGrid grid, required List<int> givens, required List<int> solution}) {
    final n = grid.cellCount;
    if (givens.length != n || solution.length != n) {
      throw FormatException('Regions givens and solution must have $n cells');
    }
    for (final cells in grid.regionCells) {
      var seen = 0;
      for (final i in cells) {
        final v = solution[i];
        if (v < 1 || v > cells.length) {
          throw FormatException('Regions solution digit $v at cell $i is outside 1..${cells.length}');
        }
        if (seen & RegionsGrid.bit(v) != 0) {
          throw FormatException('Regions solution repeats $v in region ${RegionsGrid.letters[grid.regionOf[i]]}');
        }
        seen |= RegionsGrid.bit(v);
      }
    }
    for (var i = 0; i < n; i++) {
      for (final j in grid.neighbours[i]) {
        if (j > i && solution[i] == solution[j]) {
          throw FormatException('Regions solution has equal digits touching at cells $i and $j');
        }
      }
    }
    for (var i = 0; i < n; i++) {
      final g = givens[i];
      if (g < 0 || g > grid.sizeOf(i)) throw FormatException('Regions given at cell $i is out of range: $g');
      if (g != 0 && g != solution[i]) {
        throw FormatException('Regions given at cell $i ($g) disagrees with the solution (${solution[i]})');
      }
    }
    if (RegionsSolver.countSolutions(grid, givens) != 1) {
      throw const FormatException('Regions givens do not have a unique solution');
    }
    return RegionsPuzzle._(grid, List<int>.unmodifiable(givens), List<int>.unmodifiable(solution));
  }

  const RegionsPuzzle._(this.grid, this.givens, this.solution);

  static RegionsPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final width = payload['width'];
    final height = payload['height'];
    if (width is! int || height is! int) throw const FormatException('Regions payload needs int "width" and "height"');
    final regions = payload['regions'];
    if (regions is! String) throw const FormatException('Regions payload is missing "regions"');
    final rawGivens = payload['givens'];
    if (rawGivens is! String) throw const FormatException('Regions payload is missing "givens"');
    final rawSolution = reveal['solution'];
    if (rawSolution is! String) throw const FormatException('Regions reveal is missing "solution"');
    final grid = RegionsGrid.parse(width: width, height: height, regions: regions);
    return RegionsPuzzle(
      grid: grid,
      givens: grid.parseCells(rawGivens, field: 'givens', allowBlank: true),
      solution: grid.parseCells(rawSolution, field: 'solution', allowBlank: false),
    );
  }

  final RegionsGrid grid;

  /// One value per cell, 0 for a blank.
  final List<int> givens;

  /// One digit per cell.
  final List<int> solution;

  int get width => grid.width;
  int get height => grid.height;
  int get cellCount => grid.cellCount;

  bool isGiven(int index) => givens[index] != 0;

  int get givenCount => givens.where((g) => g != 0).length;

  String get givensString => RegionsGrid.formatCells(givens);
  String get solutionString => RegionsGrid.formatCells(solution);

  Map<String, dynamic> toPayload() => {
        'width': width,
        'height': height,
        'regions': grid.regionsString,
        'givens': givensString,
      };

  Map<String, dynamic> toReveal() => {'solution': solutionString};
}
