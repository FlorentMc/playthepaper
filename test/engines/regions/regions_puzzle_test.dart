import 'package:playthepaper/engines/regions/regions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  Matcher rejects(String fragment) =>
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(fragment)));

  test('parses a valid payload and reveal', () {
    final puzzle = tinyPuzzle();
    expect(puzzle.width, 4);
    expect(puzzle.height, 2);
    expect(puzzle.grid.regionCount, 2);
    expect(puzzle.grid.regionCells[0], [0, 1, 4, 5]);
    expect(puzzle.grid.regionCells[1], [2, 3, 6, 7]);
    expect(puzzle.givens, [0, 0, 1, 2, 3, 4, 0, 0]);
    expect(puzzle.solution, [1, 2, 1, 2, 3, 4, 3, 4]);
    expect(puzzle.givenCount, 4);
    expect(puzzle.isGiven(2), isTrue);
    expect(puzzle.isGiven(0), isFalse);
    expect(puzzle.toPayload(), tinyPayload());
    expect(puzzle.toReveal(), tinyReveal());
  });

  test('region letters are renumbered in order of first appearance', () {
    final puzzle = RegionsPuzzle.parse(tinyPayload(regions: 'zzQQzzQQ'), tinyReveal());
    expect(puzzle.grid.regionsString, tinyRegions);
    expect(puzzle.toPayload(), tinyPayload());
  });

  test('the 4×4 fixture parses and exposes geometry', () {
    final puzzle = smallPuzzle();
    final grid = puzzle.grid;
    expect(grid.regionCount, 4);
    expect(grid.sizeOf(8), 1);
    expect(grid.sizeOf(0), 5);
    expect(grid.maxDigit, 5);
    expect(grid.neighbours[0], [1, 4, 5]);
    expect(grid.neighbours[5].length, 8);
    expect(grid.touches(0, 5), isTrue);
    expect(grid.touches(0, 6), isFalse);
    expect(grid.sameRegion(0, 7), isTrue);
    expect(grid.sameRegion(0, 4), isFalse);
  });

  test('rejects missing or mistyped fields', () {
    expect(() => RegionsPuzzle.parse({}, tinyReveal()), throwsFormatException);
    expect(() => RegionsPuzzle.parse(tinyPayload(), {}), throwsFormatException);
    expect(() => RegionsPuzzle.parse({...tinyPayload(), 'width': '4'}, tinyReveal()), throwsFormatException);
    expect(() => RegionsPuzzle.parse({...tinyPayload()}..remove('regions'), tinyReveal()), throwsFormatException);
    expect(() => RegionsPuzzle.parse({...tinyPayload(), 'givens': 1}, tinyReveal()), throwsFormatException);
    expect(() => RegionsPuzzle.parse(tinyPayload(), {'solution': 1}), throwsFormatException);
  });

  test('rejects boards outside 2 to 8 cells a side', () {
    expect(() => RegionsPuzzle.parse({...tinyPayload(), 'width': 9}, tinyReveal()), rejects('2 to 8'));
    expect(() => RegionsPuzzle.parse({...tinyPayload(), 'height': 1}, tinyReveal()), rejects('2 to 8'));
    expect(() => RegionsGrid(width: 0, height: 2, regionOf: const []), rejects('2 to 8'));
  });

  test('rejects wrong lengths and characters', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(regions: 'AABBAAB'), tinyReveal()), rejects('8 characters'));
    expect(() => RegionsPuzzle.parse(tinyPayload(regions: 'AABB1ABB'), tinyReveal()), rejects('invalid character'));
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '..1234.'), tinyReveal()), rejects('8 characters'));
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '..12340.'), tinyReveal()), rejects('invalid character'));
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: 'x.1234..'), tinyReveal()), rejects('invalid character'));
    expect(() => RegionsPuzzle.parse(tinyPayload(), tinyReveal('1212343')), rejects('8 characters'));
    expect(() => RegionsPuzzle.parse(tinyPayload(), tinyReveal('1212343.')), rejects('invalid character'));
  });

  test('rejects a region of six cells', () {
    expect(
      () => RegionsPuzzle.parse({'width': 3, 'height': 2, 'regions': 'AAAAAA', 'givens': '......'}, {'solution': '123456'}),
      rejects('6 cells; the most allowed is 5'),
    );
    expect(
      () => RegionsPuzzle.parse({'width': 6, 'height': 2, 'regions': 'AAAAAABBCCDD', 'givens': '.' * 12}, {'solution': '1' * 12}),
      rejects('the most allowed is 5'),
    );
  });

  test('rejects a region that is not connected', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(regions: 'ABABCCCC'), tinyReveal()), rejects('not connected'));
    expect(
      () => RegionsGrid(width: 2, height: 2, regionOf: const [0, 1, 1, 0]),
      rejects('not connected'),
    );
  });

  test('rejects a layout whose region indices skip a number', () {
    expect(() => RegionsGrid(width: 2, height: 2, regionOf: const [0, 0, 2, 2]), rejects('skips'));
    expect(() => RegionsGrid(width: 2, height: 2, regionOf: const [0, 0, -1, 0]), rejects('bad region'));
  });

  test('rejects a solution with a region missing a digit', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '........'), tinyReveal(tinyMissingDigit)), rejects('repeats 3 in region B'));
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '........'), tinyReveal('12153434')), rejects('outside 1..4'));
    expect(RegionsGrid.parse(width: 4, height: 2, regions: tinyRegions).isValidSolution([1, 2, 1, 3, 3, 4, 3, 4]), isFalse);
  });

  test('rejects a solution where equal digits touch at a corner', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '........'), tinyReveal(tinyDiagonalTouch)), rejects('touching at cells 2 and 5'));
    final grid = RegionsGrid.parse(width: 4, height: 2, regions: tinyRegions);
    expect(grid.isValidSolution(cells(grid, tinyDiagonalTouch, allowBlank: false)), isFalse);
    expect(grid.violations(cells(grid, tinyDiagonalTouch)), {2, 5});
  });

  test('rejects a solution where equal digits share a side', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '........'), tinyReveal(tinySideTouch)), rejects('touching at cells 1 and 2'));
  });

  test('rejects givens that disagree with the solution or exceed their region', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '2.1234..'), tinyReveal()), rejects('disagrees'));
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '5.1234..'), tinyReveal()), rejects('out of range'));
    expect(
      () => RegionsPuzzle(grid: smallPuzzle().grid, givens: List.filled(16, 0)..[8] = 2, solution: smallPuzzle().solution),
      rejects('out of range'),
    );
  });

  test('rejects givens with more than one solution', () {
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: tinyTwoSolutionGivens), tinyReveal()), rejects('unique'));
    expect(() => RegionsPuzzle.parse(tinyPayload(givens: '........'), tinyReveal()), rejects('unique'));
  });

  test('the constructor validates raw lists', () {
    final grid = RegionsGrid.parse(width: 4, height: 2, regions: tinyRegions);
    expect(() => RegionsPuzzle(grid: grid, givens: List.filled(7, 0), solution: cells(grid, tinySolution)), rejects('8 cells'));
    expect(() => RegionsGrid.parse(width: 4, height: 2, regions: 'ABCDEFGH'), returnsNormally);
  });

  test('cell strings round trip', () {
    final grid = RegionsGrid.parse(width: 4, height: 2, regions: tinyRegions);
    expect(RegionsGrid.formatCells(cells(grid, tinyGivens)), tinyGivens);
    expect(RegionsGrid.digitsUpTo(5), 0x3E);
    expect(RegionsGrid.digitsUpTo(1), 0x02);
    expect(RegionsGrid.digitsOf(0x2A).toList(), [1, 3, 5]);
    expect(RegionsGrid.bitCount(0x2A), 3);
    expect(RegionsGrid.lowestDigit(0x28), 3);
  });
}
