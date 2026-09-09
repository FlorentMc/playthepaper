import 'target_expression.dart';

/// A validated puzzle: six tiles, a target, and one known solution.
///
/// Payload: `{"tiles": [25, 7, 4, 3, 2, 1], "target": 431}`.
/// Reveal: `{"expression": "25 * 7 * (4 - 2) + 3 * 1"}`.
class TargetPuzzle {
  /// Validates the tiles, the target range and that [expression] reaches
  /// the target under the rules. Throws [FormatException] otherwise.
  factory TargetPuzzle({required List<int> tiles, required int target, required String expression}) {
    if (tiles.length != tileCount) throw FormatException('Target needs $tileCount tiles, got ${tiles.length}');
    var large = 0;
    for (final t in tiles) {
      if (largeTiles.contains(t)) {
        large++;
      } else if (t < minSmall || t > maxSmall) {
        throw FormatException('Target tile $t must be $minSmall–$maxSmall or one of $largeTiles');
      }
    }
    if (large != largeCount) throw FormatException('Target needs $largeCount large tiles, got $large');
    if (target < minTarget || target > maxTarget) {
      throw FormatException('Target must be $minTarget–$maxTarget, got $target');
    }
    final parsed = TargetExpression.parse(expression);
    final value = parsed.value(tiles);
    if (value != target) throw FormatException('Target expression makes $value, not $target');
    return TargetPuzzle._(List<int>.unmodifiable(tiles), target, parsed);
  }

  const TargetPuzzle._(this.tiles, this.target, this.solution);

  static const int tileCount = 6;
  static const int largeCount = 2;
  static const List<int> largeTiles = [25, 50, 75, 100];
  static const int minSmall = 1;
  static const int maxSmall = 10;
  static const int minTarget = 101;
  static const int maxTarget = 999;

  static TargetPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawTiles = payload['tiles'];
    if (rawTiles is! List || rawTiles.any((t) => t is! int)) {
      throw const FormatException('Target payload needs "tiles" as a list of ints');
    }
    final rawTarget = payload['target'];
    if (rawTarget is! int) throw const FormatException('Target payload is missing "target"');
    final rawExpression = reveal['expression'];
    if (rawExpression is! String || rawExpression.isEmpty) {
      throw const FormatException('Target reveal is missing "expression"');
    }
    return TargetPuzzle(tiles: rawTiles.cast<int>(), target: rawTarget, expression: rawExpression);
  }

  final List<int> tiles;
  final int target;

  /// One known way of reaching the target.
  final TargetExpression solution;

  Map<String, dynamic> toPayload() => {'tiles': List<int>.of(tiles), 'target': target};
  Map<String, dynamic> toReveal() => {'expression': solution.text};
}
