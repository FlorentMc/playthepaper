import 'package:playthepaper/engines/target/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> payload({List<int> tiles = const [25, 7, 4, 3, 2, 1], int target = 353}) =>
      {'tiles': tiles, 'target': target};
  Map<String, dynamic> reveal([String expression = '25 * 7 * (4 - 2) + 3 * 1']) => {'expression': expression};

  test('parses a valid payload and reveal', () {
    final puzzle = TargetPuzzle.parse(payload(tiles: [25, 50, 7, 4, 3, 2], target: 353), reveal('25 * 7 * (4 - 2) + 3'));
    expect(puzzle.tiles, [25, 50, 7, 4, 3, 2]);
    expect(puzzle.target, 353);
    expect(puzzle.solution.text, '25 * 7 * (4 - 2) + 3');
    expect(puzzle.toPayload(), {'tiles': [25, 50, 7, 4, 3, 2], 'target': 353});
    expect(puzzle.toReveal(), {'expression': '25 * 7 * (4 - 2) + 3'});
  });

  test('rejects missing or mistyped fields', () {
    expect(() => TargetPuzzle.parse({}, reveal()), throwsFormatException);
    expect(() => TargetPuzzle.parse({'tiles': [25, 50, 7, 4, 3, 2]}, reveal()), throwsFormatException);
    expect(() => TargetPuzzle.parse({'tiles': 'x', 'target': 353}, reveal()), throwsFormatException);
    expect(() => TargetPuzzle.parse({'tiles': [25, 50, 7, 4, 3, '2'], 'target': 353}, reveal()), throwsFormatException);
    expect(() => TargetPuzzle.parse(payload(), {}), throwsFormatException);
    expect(() => TargetPuzzle.parse(payload(), {'expression': ''}), throwsFormatException);
  });

  test('rejects the wrong number or kind of tiles', () {
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 50, 7, 4, 3]), reveal('25 + 50 + 7 + 4 + 3')), throwsFormatException);
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 7, 4, 3, 2, 1]), reveal()), throwsFormatException, reason: 'one large');
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 50, 75, 3, 2, 1]), reveal('25 + 50 + 75')), throwsFormatException, reason: 'three large');
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 50, 11, 3, 2, 1], target: 150), reveal('100 + 50')), throwsFormatException);
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 50, 0, 3, 2, 1], target: 150), reveal('100 + 50')), throwsFormatException);
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 60, 3, 3, 2, 1], target: 150), reveal('100 + 50')), throwsFormatException);
  });

  test('rejects a target out of range', () {
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 50, 7, 4, 3, 2], target: 100), reveal('50 * 2')), throwsFormatException);
    expect(() => TargetPuzzle.parse(payload(tiles: [25, 50, 7, 4, 3, 2], target: 1000), reveal('50 * 4 * 5')), throwsFormatException);
  });

  test('rejects a reveal that does not reach the target under the rules', () {
    const tiles = [25, 50, 7, 4, 3, 2];
    expect(() => TargetPuzzle.parse(payload(tiles: tiles, target: 353), reveal('25 * 7 * 2')), throwsFormatException, reason: 'wrong value');
    expect(() => TargetPuzzle.parse(payload(tiles: tiles, target: 353), reveal('25 * 7 * (4 - 2) + 3 * 1')), throwsFormatException, reason: 'no tile 1');
    expect(() => TargetPuzzle.parse(payload(tiles: tiles, target: 350), reveal('25 * 7 * 2 * 2 / 2')), throwsFormatException, reason: 'tile twice');
    expect(() => TargetPuzzle.parse(payload(tiles: tiles, target: 175), reveal('7 * (2 - 4) * (3 - 50) / 2 + 25')), throwsFormatException, reason: 'negative');
    expect(() => TargetPuzzle.parse(payload(tiles: tiles, target: 175), reveal('7 * 50 / 4 * 2')), throwsFormatException, reason: 'inexact');
    expect(() => TargetPuzzle.parse(payload(tiles: tiles, target: 175), reveal('7 * 50 /')), throwsFormatException, reason: 'malformed');
  });
}
