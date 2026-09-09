import 'package:playthepaper/engines/regions/regions.dart';

/// A 4×2 board of two 2×2 regions. Row 0 is `1 2 1 2`, row 1 is `3 4 3 4`.
const tinyWidth = 4;
const tinyHeight = 2;
const tinyRegions = 'AABBAABB';
const tinyGivens = '..1234..';
const tinySolution = '12123434';

/// The same board with one fewer given: `4` and `3` can swap in the last
/// column, so it has exactly two solutions.
const tinyTwoSolutionGivens = '..123...';

/// Both regions hold 1–4, but the 4s at (0,2) and (1,1) touch at a corner.
const tinyDiagonalTouch = '12433412';

/// Both regions hold 1–4, but the 2s at (0,1) and (0,2) share a side.
const tinySideTouch = '12213434';

/// Region B holds 1, 3, 3, 4: no 2.
const tinyMissingDigit = '12133434';

/// A 4×4 board with three regions of five and one lone cell.
const smallWidth = 4;
const smallHeight = 4;
const smallRegions = 'AAAACCCADBCCBBBB';
const smallGivens = '.45........3..2.';
const smallSolution = '1453521213434521';

Map<String, dynamic> tinyPayload({String givens = tinyGivens, String regions = tinyRegions}) =>
    {'width': tinyWidth, 'height': tinyHeight, 'regions': regions, 'givens': givens};

Map<String, dynamic> tinyReveal([String solution = tinySolution]) => {'solution': solution};

Map<String, dynamic> smallPayload({String givens = smallGivens}) =>
    {'width': smallWidth, 'height': smallHeight, 'regions': smallRegions, 'givens': givens};

Map<String, dynamic> smallReveal([String solution = smallSolution]) => {'solution': solution};

RegionsPuzzle tinyPuzzle() => RegionsPuzzle.parse(tinyPayload(), tinyReveal());

RegionsPuzzle smallPuzzle() => RegionsPuzzle.parse(smallPayload(), smallReveal());

List<int> cells(RegionsGrid grid, String text, {bool allowBlank = true}) =>
    grid.parseCells(text, field: 'fixture', allowBlank: allowBlank);
