import 'package:playthepaper/engines/kakuro/kakuro.dart';

/// A 3×3 board with four white cells and one solution: 1 2 / 3 1.
Map<String, dynamic> smallPayload() => {
      'width': 3,
      'height': 3,
      'cells': [
        '#',
        {'down': 4, 'across': null},
        {'down': 3, 'across': null},
        {'down': null, 'across': 3},
        '.',
        '.',
        {'down': null, 'across': 4},
        '.',
        '.',
      ],
    };

Map<String, dynamic> smallReveal() => {
      'solution': ['#', '#', '#', '#', '1', '2', '#', '3', '1'],
    };

/// The same shape with every clue 3: 1 2 / 2 1 and 2 1 / 1 2 both fit.
Map<String, dynamic> twoSolutionPayload() => {
      'width': 3,
      'height': 3,
      'cells': [
        '#',
        {'down': 3, 'across': null},
        {'down': 3, 'across': null},
        {'down': null, 'across': 3},
        '.',
        '.',
        {'down': null, 'across': 3},
        '.',
        '.',
      ],
    };

Map<String, dynamic> twoSolutionReveal() => {
      'solution': ['#', '#', '#', '#', '1', '2', '#', '2', '1'],
    };

/// Clues that 2 2 / 2 4 meets by sum alone: every run adds up, but two of
/// them repeat a digit.
Map<String, dynamic> repeatPayload() => {
      'width': 3,
      'height': 3,
      'cells': [
        '#',
        {'down': 4, 'across': null},
        {'down': 6, 'across': null},
        {'down': null, 'across': 4},
        '.',
        '.',
        {'down': null, 'across': 6},
        '.',
        '.',
      ],
    };

Map<String, dynamic> repeatReveal() => {
      'solution': ['#', '#', '#', '#', '2', '2', '#', '2', '4'],
    };

/// 3 across and 3 down force 1 and 2 into the top-left; 17 down needs 8 and
/// 9 in the right column, so the bottom row cannot add up to 4.
Map<String, dynamic> impossiblePayload() => {
      'width': 3,
      'height': 3,
      'cells': [
        '#',
        {'down': 3, 'across': null},
        {'down': 17, 'across': null},
        {'down': null, 'across': 3},
        '.',
        '.',
        {'down': null, 'across': 4},
        '.',
        '.',
      ],
    };

KakuroPuzzle smallPuzzle() => KakuroPuzzle.parse(smallPayload(), smallReveal());

KakuroGrid gridOf(Map<String, dynamic> payload) => KakuroGrid.parsePayload(payload);
