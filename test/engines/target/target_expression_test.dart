import 'package:playthepaper/engines/target/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tiles = [25, 7, 4, 3, 2, 1];

  test('parses and evaluates with precedence and parentheses', () {
    expect(TargetExpression.evaluate('25 * 7 * (4 - 2) + 3 * 1', tiles), 353);
    expect(TargetExpression.evaluate('25*7*(4-2)+3*1', tiles), 353);
    expect(TargetExpression.evaluate('(25 + 7) * 4', tiles), 128);
    expect(TargetExpression.evaluate('25 + 7 * 4', tiles), 53);
    expect(TargetExpression.evaluate('25 × 4 − 7 ÷ 1', tiles), 93);
    expect(TargetExpression.evaluate('7', tiles), 7);
  });

  test('renders with the fewest parentheses and round-trips', () {
    for (final text in ['25 * 7 * (4 - 2) + 3 * 1', '25 - (7 - 4)', '25 / (7 - 2)', '(25 - 7) - 4', '25 - 7 - 4', '(25 + 7) * 4']) {
      final e = TargetExpression.parse(text);
      expect(TargetExpression.parse(e.text).value(tiles), e.value(tiles), reason: text);
    }
    expect(TargetExpression.parse('(25 - (7 - 4))').text, '25 - (7 - 4)');
    expect(TargetExpression.parse('((25 - 7) - 4)').text, '25 - 7 - 4');
    expect(TargetExpression.parse('((25 + 7) * 4)').text, '(25 + 7) * 4');
    expect(TargetExpression.parse('25 - 7').display, '25 − 7');
    expect(TargetExpression.parse('25 * 7 / 1').display, '25 × 7 ÷ 1');
    expect(TargetExpression.parse('25 * 7 + 4').numbers, [25, 7, 4]);
  });

  test('rejects malformed text', () {
    for (final bad in ['', '25 +', '+ 25', '(25', '25) + 7', 'abc', '25 7', '25 ** 7', '25 + (7 *)', '-25']) {
      expect(() => TargetExpression.parse(bad), throwsFormatException, reason: bad);
    }
  });

  test('rejects a result that is not positive', () {
    expect(() => TargetExpression.evaluate('3 - 7', tiles), throwsFormatException);
    expect(() => TargetExpression.evaluate('25 * (3 - 4) + 7', tiles), throwsFormatException);
    expect(() => TargetExpression.evaluate('(3 - 3) + 7', [3, 3, 7]), throwsFormatException);
    expect(TargetOp.subtract.apply(3, 7), isNull);
    expect(TargetOp.subtract.apply(7, 7), isNull);
  });

  test('rejects inexact division', () {
    expect(() => TargetExpression.evaluate('7 / 2', tiles), throwsFormatException);
    expect(() => TargetExpression.evaluate('25 / (7 - 4)', tiles), throwsFormatException);
    expect(TargetOp.divide.apply(7, 2), isNull);
    expect(TargetOp.divide.apply(8, 2), 4);
  });

  test('rejects a tile used twice or not on the table', () {
    expect(() => TargetExpression.evaluate('25 + 25', tiles), throwsFormatException);
    expect(() => TargetExpression.evaluate('3 * 3', tiles), throwsFormatException);
    expect(TargetExpression.evaluate('3 * 3', [3, 3]), 9);
    expect(() => TargetExpression.evaluate('50 + 1', tiles), throwsFormatException);
    expect(() => TargetExpression.evaluate('0 + 1', tiles), throwsFormatException);
  });

  test('operations map from every symbol', () {
    expect(TargetOp.fromChar('+'), TargetOp.add);
    expect(TargetOp.fromChar('-'), TargetOp.subtract);
    expect(TargetOp.fromChar('−'), TargetOp.subtract);
    expect(TargetOp.fromChar('*'), TargetOp.multiply);
    expect(TargetOp.fromChar('x'), TargetOp.multiply);
    expect(TargetOp.fromChar('×'), TargetOp.multiply);
    expect(TargetOp.fromChar('/'), TargetOp.divide);
    expect(TargetOp.fromChar('÷'), TargetOp.divide);
    expect(TargetOp.fromChar('?'), isNull);
  });
}
