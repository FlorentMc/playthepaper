import 'package:playthepaper/engines/loop/loop.dart';

/// A 3×3 board whose loop runs around cells (0,0), (0,1), (1,1) and (1,2):
///
///     +---+---+   +
///     | 3   2 | 2
///     +   +   +---+
///       2 | 2   3 |
///     +   +---+---+
///       0   1   1
///     +   +   +   +
const smallClues = '322223011';
const smallH = ['110', '101', '011', '000'];
const smallV = ['1010', '0101', '0000'];

Map<String, dynamic> smallPayload({String clues = smallClues, int width = 3, int height = 3}) =>
    {'width': width, 'height': height, 'clues': clues};

Map<String, dynamic> smallReveal({Object h = smallH, Object v = smallV}) => {
      'edges': {'h': h, 'v': v},
    };

LoopPuzzle smallPuzzle() => LoopPuzzle.parse(smallPayload(), smallReveal());

/// Three of those clues, still unique; needs one-step reasoning.
const smallSparseClues = '...2.30..';

/// Four clues that the counting rules alone settle.
const smallTrivialClues = '...2230..';

/// Four clues that are unique but need deeper search.
const smallHardClues = '..2223...';

/// Lines from row strings, horizontal rows first.
List<bool> linesOf(List<String> h, List<String> v) => [...h.join().split(''), ...v.join().split('')].map((c) => c == '1').toList();

/// Two separate unit loops, around cells (0,0) and (2,2), on a 3×3 board.
const twoLoopsH = ['100', '100', '001', '001'];
const twoLoopsV = ['1100', '0000', '0011'];

/// Clues every one of which those two loops satisfy.
const twoLoopsClues = '.1010101.';
