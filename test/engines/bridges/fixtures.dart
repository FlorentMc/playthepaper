import 'package:playthepaper/engines/bridges/bridges.dart';

Map<String, dynamic> island(int row, int col, int count) => {'row': row, 'col': col, 'count': count};
Map<String, dynamic> bridge(int from, int to, int count) => {'from': from, 'to': to, 'count': count};

/// Four 2s on the corners of a 3×3 board. The only connected answer is a
/// ring of single bridges; pairs are 0: A–B, 1: A–C, 2: B–D, 3: C–D.
///
///     A(2) - B(2)
///      |      |
///     C(2) - D(2)
final Map<String, dynamic> ringPayload = {
  'width': 3,
  'height': 3,
  'islands': [island(0, 0, 2), island(0, 2, 2), island(2, 0, 2), island(2, 2, 2)],
};
final Map<String, dynamic> ringReveal = {
  'bridges': [bridge(0, 1, 1), bridge(0, 2, 1), bridge(1, 3, 1), bridge(2, 3, 1)],
};
const List<int> ringSolution = [1, 1, 1, 1];

/// Same corners, all 3s: a double bridge can sit on either the top and
/// bottom or the left and right, so two connected answers exist.
final Map<String, dynamic> twoSolutionsPayload = {
  'width': 3,
  'height': 3,
  'islands': [island(0, 0, 3), island(0, 2, 3), island(2, 0, 3), island(2, 2, 3)],
};
final Map<String, dynamic> twoSolutionsReveal = {
  'bridges': [bridge(0, 1, 1), bridge(0, 2, 2), bridge(1, 3, 2), bridge(2, 3, 1)],
};

/// Four 1s around an empty centre: the only two pairs cross, so there is
/// no answer at all.
final Map<String, dynamic> plusPayload = {
  'width': 3,
  'height': 3,
  'islands': [island(0, 1, 1), island(1, 0, 1), island(1, 2, 1), island(2, 1, 1)],
};

/// A straight line, settled by counting alone.
final Map<String, dynamic> chainPayload = {
  'width': 5,
  'height': 2,
  'islands': [island(0, 0, 1), island(0, 2, 2), island(0, 4, 1)],
};
final Map<String, dynamic> chainReveal = {
  'bridges': [bridge(0, 1, 1), bridge(1, 2, 1)],
};

/// A unique puzzle with a crossing candidate: A–D (pair 2, vertical) and
/// B–C (pair 3, horizontal) meet at the empty centre. The answer uses B–C.
///
///     F(2) - A(1)
///      |      :
///     B(3) - : - C(1)
///      |      :
///     G(2) - D(1)
final Map<String, dynamic> crossingPayload = {
  'width': 5,
  'height': 5,
  'islands': [
    island(0, 0, 2),
    island(0, 2, 1),
    island(2, 0, 3),
    island(2, 4, 1),
    island(4, 2, 1),
    island(4, 0, 2),
  ],
};
final Map<String, dynamic> crossingReveal = {
  'bridges': [bridge(0, 1, 1), bridge(0, 2, 1), bridge(2, 3, 1), bridge(2, 5, 1), bridge(5, 4, 1)],
};
const int crossingVerticalPair = 2;
const int crossingHorizontalPair = 3;

/// The same shape without G, whose reveal meets every count and joins every
/// island but crosses at the centre.
final Map<String, dynamic> crossedPayload = {
  'width': 5,
  'height': 5,
  'islands': [island(0, 0, 2), island(0, 2, 2), island(2, 0, 2), island(2, 4, 1), island(4, 2, 1)],
};
final Map<String, dynamic> crossedReveal = {
  'bridges': [bridge(0, 1, 1), bridge(0, 2, 1), bridge(1, 4, 1), bridge(2, 3, 1)],
};

/// Seven islands on 5×5 that propagation cannot finish without a guess.
final Map<String, dynamic> hardPayload = {
  'width': 5,
  'height': 5,
  'islands': [
    island(2, 0, 3),
    island(0, 0, 2),
    island(0, 4, 3),
    island(4, 0, 2),
    island(4, 4, 1),
    island(2, 4, 2),
    island(2, 2, 1),
  ],
};
final Map<String, dynamic> hardReveal = {
  'bridges': [bridge(0, 6, 1), bridge(0, 3, 1), bridge(1, 2, 1), bridge(1, 0, 1), bridge(2, 5, 2), bridge(3, 4, 1)],
};

BridgesPuzzle ringPuzzle() => BridgesPuzzle.parse(ringPayload, ringReveal);
BridgesPuzzle crossingPuzzle() => BridgesPuzzle.parse(crossingPayload, crossingReveal);

Map<String, dynamic> withIslands(Map<String, dynamic> payload, List<Map<String, dynamic>> islands) =>
    {...payload, 'islands': islands};
