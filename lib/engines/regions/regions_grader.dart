import 'regions_grid.dart';

/// The techniques a solver applies, easiest first.
enum RegionsTechnique {
  /// A cell with a single candidate.
  nakedSingle,

  /// A digit with a single possible cell in its region.
  hiddenSingle,

  /// A digit whose possible cells in one region all touch a cell outside
  /// it, so that cell cannot hold the digit.
  locked,

  /// The techniques above do not finish the puzzle.
  search,
}

/// How a puzzle yields to human techniques.
class RegionsRating {
  const RegionsRating({
    required this.nakedSingles,
    required this.hiddenSingles,
    required this.lockedSteps,
    required this.solvedByLogic,
  });

  final int nakedSingles;
  final int hiddenSingles;
  final int lockedSteps;

  /// True when singles and locked candidates alone fill the board.
  final bool solvedByLogic;

  RegionsTechnique get hardest {
    if (!solvedByLogic) return RegionsTechnique.search;
    if (lockedSteps > 0) return RegionsTechnique.locked;
    if (hiddenSingles > 0) return RegionsTechnique.hiddenSingle;
    return RegionsTechnique.nakedSingle;
  }

  @override
  String toString() =>
      'RegionsRating(naked: $nakedSingles, hidden: $hiddenSingles, locked: $lockedSteps, logic: $solvedByLogic)';
}

/// Solves with human techniques only, counting each step, to rate a puzzle
/// and to reject ones that are trivial or need guessing.
class RegionsGrader {
  RegionsGrader._();

  static RegionsRating grade(RegionsGrid grid, List<int> givens) {
    final n = grid.cellCount;
    final values = List<int>.of(givens, growable: false);
    final cand = List<int>.generate(n, (i) => RegionsGrid.digitsUpTo(grid.sizeOf(i)), growable: false);
    var naked = 0, hidden = 0, locked = 0;

    void place(int i, int d) {
      final b = RegionsGrid.bit(d);
      values[i] = d;
      cand[i] = b;
      for (final j in grid.neighbours[i]) {
        if (values[j] == 0) cand[j] &= ~b;
      }
      for (final j in grid.regionCells[grid.regionOf[i]]) {
        if (values[j] == 0) cand[j] &= ~b;
      }
    }

    for (var i = 0; i < n; i++) {
      if (values[i] != 0) place(i, values[i]);
    }

    bool nakedSingle() {
      for (var i = 0; i < n; i++) {
        final m = cand[i];
        if (values[i] == 0 && m != 0 && m & (m - 1) == 0) {
          place(i, RegionsGrid.lowestDigit(m));
          return true;
        }
      }
      return false;
    }

    bool hiddenSingle() {
      for (final cells in grid.regionCells) {
        for (var d = 1; d <= cells.length; d++) {
          final b = RegionsGrid.bit(d);
          var where = -1;
          var count = 0;
          for (final i in cells) {
            if (values[i] == d) {
              count = -1;
              break;
            }
            if (values[i] == 0 && cand[i] & b != 0) {
              count++;
              where = i;
            }
          }
          if (count == 1) {
            place(where, d);
            return true;
          }
        }
      }
      return false;
    }

    bool lockedCandidates() {
      var eliminated = false;
      for (var r = 0; r < grid.regionCount; r++) {
        final cells = grid.regionCells[r];
        for (var d = 1; d <= cells.length; d++) {
          final b = RegionsGrid.bit(d);
          if (cells.any((i) => values[i] == d)) continue;
          final spots = cells.where((i) => values[i] == 0 && cand[i] & b != 0).toList(growable: false);
          if (spots.length < 2) continue;
          final shared = <int>{...grid.neighbours[spots.first]};
          for (final s in spots.skip(1)) {
            shared.retainWhere((c) => grid.neighbours[s].contains(c));
          }
          for (final c in shared) {
            if (grid.regionOf[c] == r || values[c] != 0 || cand[c] & b == 0) continue;
            cand[c] &= ~b;
            eliminated = true;
          }
        }
      }
      return eliminated;
    }

    while (values.contains(0)) {
      if (nakedSingle()) {
        naked++;
      } else if (hiddenSingle()) {
        hidden++;
      } else if (lockedCandidates()) {
        locked++;
      } else {
        break;
      }
    }
    return RegionsRating(
      nakedSingles: naked,
      hiddenSingles: hidden,
      lockedSteps: locked,
      solvedByLogic: !values.contains(0),
    );
  }
}
