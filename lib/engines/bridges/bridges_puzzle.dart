import 'bridges_layout.dart';
import 'bridges_solver.dart';

/// A validated puzzle: the board, its islands and their unique solution.
///
/// Payload: `{"width": 7, "height": 7, "islands": [{"row": 0, "col": 0, "count": 3}]}`.
/// Reveal: `{"bridges": [{"from": 0, "to": 1, "count": 2}]}`, indices into
/// the islands, one entry per bridged pair.
class BridgesPuzzle {
  /// Validates the reveal against every rule and proves it is the only
  /// solution. Throws [FormatException] otherwise.
  factory BridgesPuzzle({required BridgesLayout layout, required List<int> solution}) {
    if (solution.length != layout.pairs.length) {
      throw FormatException('Bridges solution must cover ${layout.pairs.length} pairs');
    }
    final fault = layout.firstFault(solution);
    if (fault != null) throw FormatException('Bridges solution is wrong: ${fault.message}');
    if (BridgesSolver.countSolutions(layout) != 1) {
      throw const FormatException('Bridges puzzle does not have a unique solution');
    }
    return BridgesPuzzle._(layout, List<int>.unmodifiable(solution));
  }

  const BridgesPuzzle._(this.layout, this.solution);

  static BridgesPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final layout = BridgesLayout.parse(payload);
    final raw = reveal['bridges'];
    if (raw is! List) throw const FormatException('Bridges reveal is missing "bridges"');
    final solution = List<int>.filled(layout.pairs.length, 0);
    for (var k = 0; k < raw.length; k++) {
      final entry = raw[k];
      if (entry is! Map) throw FormatException('Bridges reveal bridge $k must be an object');
      final from = entry['from'], to = entry['to'], count = entry['count'];
      if (from is! int || to is! int || count is! int) {
        throw FormatException('Bridges reveal bridge $k needs integer "from", "to" and "count"');
      }
      if (from < 0 || from >= layout.islands.length || to < 0 || to >= layout.islands.length || from == to) {
        throw FormatException('Bridges reveal bridge $k joins islands that do not exist');
      }
      if (count < 1 || count > BridgesLayout.maxBridges) {
        throw FormatException('Bridges reveal bridge $k must carry 1 or ${BridgesLayout.maxBridges} bridges, not $count');
      }
      final pair = layout.pairBetween(from, to);
      if (pair == null) {
        throw FormatException('Bridges reveal bridge $k: islands $from and $to are not in line with a clear path');
      }
      if (solution[pair] != 0) throw FormatException('Bridges reveal lists islands $from and $to twice');
      solution[pair] = count;
    }
    return BridgesPuzzle(layout: layout, solution: solution);
  }

  final BridgesLayout layout;

  /// Bridges per pair in the unique solution.
  final List<int> solution;

  int get islandCount => layout.islands.length;

  int get bridgeCount => solution.fold(0, (a, b) => a + b);

  Map<String, dynamic> toPayload() => layout.toPayload();

  Map<String, dynamic> toReveal() => {
        'bridges': [
          for (final pair in layout.pairs)
            if (solution[pair.index] > 0) {'from': pair.a, 'to': pair.b, 'count': solution[pair.index]},
        ],
      };
}
