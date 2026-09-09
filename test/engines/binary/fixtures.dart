import 'package:playthepaper/engines/binary/binary.dart';

/// A valid 4×4 solution.
const solution4 = '0110100101011010';

/// A valid 6×6 solution and a set of givens that propagation alone solves.
const solution6 = '001101010011100110011001110010101100';
const givens6 = '0.1101.100..1...10.110.11.0....0.1..';

/// Equal counts everywhere, distinct lines, but runs of three.
const tripleOnly6 = '000111001110011100100011110001111000';

/// Equal counts, no runs of three, but rows 3 and 6 are the same.
const duplicateRows6 = '001011001101110010010101101100110010';

/// One cell flipped in a valid grid: a row and a column have unequal counts.
const unequalCounts6 = '100100011010001011100101010110101001';

/// Blanking the checkerboard at rows 1–2, columns 2–3 of [solution6] leaves
/// two solutions: the original and the one with those four cells swapped.
const twoSolutionCells = [1, 2, 7, 8];

List<int> cells(String text, int size, {bool allowBlank = true}) =>
    BinaryRules.parseCells(text, size, field: 'fixture', allowBlank: allowBlank);

String transpose(String text, int size) {
  final g = cells(text, size);
  return List.generate(size * size, (i) => g[(i % size) * size + i ~/ size]).map((v) => '$v').join();
}

List<int> twoSolutionGrid() {
  final grid = cells(solution6, 6);
  for (final i in twoSolutionCells) {
    grid[i] = BinaryRules.empty;
  }
  return grid;
}
