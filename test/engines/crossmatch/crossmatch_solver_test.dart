import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/crossmatch/crossmatch.dart';

import 'fixtures.dart';

void main() {
  test('counts the ways every tile can take a cell it fits', () {
    expect(
      CrossmatchSolver.countMatchings([
        [0],
        [1],
      ]),
      1,
    );
    expect(
      CrossmatchSolver.countMatchings([
        [0, 1],
        [0, 1],
      ]),
      2,
    );
    expect(
      CrossmatchSolver.countMatchings([
        [0, 1, 2],
        [0, 1, 2],
        [0, 1, 2],
      ]),
      6,
    );
  });

  test('finds no matching when two tiles want the only cell they fit', () {
    expect(
      CrossmatchSolver.countMatchings([
        [0],
        [0],
      ]),
      0,
    );
    expect(
      CrossmatchSolver.solve([
        [0],
        [0],
      ]),
      isNull,
    );
  });

  test('finds no matching when a cell suits nobody', () {
    expect(
      CrossmatchSolver.countMatchings([
        [0, 1],
        [0, 1],
        [0, 1],
      ]),
      0,
    );
  });

  test('solves only when the matching is the only one', () {
    expect(
      CrossmatchSolver.solve([
        [1],
        [0, 1],
      ]),
      [1, 0],
    );
    expect(
      CrossmatchSolver.solve([
        [0, 1],
        [0, 1],
      ]),
      isNull,
      reason: 'two matchings is not a puzzle',
    );
  });

  test('agrees with the grid the author wrote', () {
    final puzzle = CrossmatchPuzzle.parse(placesPayload(), placesReveal());
    final fits = [for (final cells in puzzle.fits) cells];
    expect(CrossmatchSolver.countMatchings(fits), 1);
    final assignment = CrossmatchSolver.solve(fits)!;
    for (var tile = 0; tile < CrossmatchPuzzle.cellCount; tile++) {
      expect(assignment[tile], puzzle.cellOf(tile), reason: puzzle.tiles[tile]);
    }
  });

  test('a tile that suits two cells is pinned down by the tile that suits one', () {
    final reveal = placesReveal();
    (reveal['fits'] as Map)['Okinawa'] = [
      [1, 1],
      [1, 2],
    ];
    final puzzle = CrossmatchPuzzle.parse(placesPayload(), reveal);
    expect(CrossmatchSolver.countMatchings([for (final cells in puzzle.fits) cells]), 1);
  });
}
