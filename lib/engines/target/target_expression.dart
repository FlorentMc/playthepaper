/// The four operations of the game, with the symbol shown on screen and the
/// ASCII form written in content.
enum TargetOp {
  add('+', '+'),
  subtract('−', '-'),
  multiply('×', '*'),
  divide('÷', '/');

  const TargetOp(this.symbol, this.ascii);

  final String symbol;
  final String ascii;

  /// Order of evaluation: additive 1, multiplicative 2.
  int get precedence => this == add || this == subtract ? 1 : 2;

  /// The result of `a op b` under the rules, or null when it would not be a
  /// positive whole number.
  int? apply(int a, int b) {
    switch (this) {
      case add:
        return a + b;
      case subtract:
        return a > b ? a - b : null;
      case multiply:
        return a * b;
      case divide:
        return b != 0 && a % b == 0 ? a ~/ b : null;
    }
  }

  static TargetOp? fromChar(String ch) {
    for (final op in values) {
      if (ch == op.symbol || ch == op.ascii) return op;
    }
    if (ch == 'x' || ch == 'X') return multiply;
    if (ch == ':') return divide;
    return null;
  }
}

/// A parsed arithmetic expression over whole numbers with `+ - * /` and
/// parentheses. Evaluation enforces the game rules: every intermediate
/// result is a positive whole number, division is exact, and every number
/// is one of the tiles, each used at most once.
sealed class TargetExpression {
  const TargetExpression();

  static TargetExpression parse(String text) {
    final parser = _Parser(text);
    final expression = parser.expression();
    parser.skipSpaces();
    if (!parser.atEnd) throw FormatException('Unexpected "${parser.peek}" at ${parser.pos} in "$text"');
    return expression;
  }

  /// The value of [text] played with [tiles]. Throws [FormatException] when
  /// the expression is malformed or breaks a rule.
  static int evaluate(String text, List<int> tiles) => parse(text).value(tiles);

  /// Evaluates against [tiles], consuming each tile at most once.
  int value(List<int> tiles) => _value(List<int>.of(tiles));

  int _value(List<int> pool);

  /// The tiles the expression uses, in reading order.
  List<int> get numbers;

  int get _precedence;

  String _render(String Function(TargetOp) symbol);

  /// ASCII text with the fewest parentheses needed.
  String get text => _render((o) => o.ascii);

  /// Text with the on-screen symbols.
  String get display => _render((o) => o.symbol);

  @override
  String toString() => text;
}

class TargetNumber extends TargetExpression {
  const TargetNumber(this.number);

  final int number;

  @override
  int _value(List<int> pool) {
    if (!pool.remove(number)) throw FormatException('Tile $number is not available');
    return number;
  }

  @override
  List<int> get numbers => [number];

  @override
  int get _precedence => 3;

  @override
  String _render(String Function(TargetOp) symbol) => '$number';
}

class TargetBinary extends TargetExpression {
  const TargetBinary(this.left, this.op, this.right);

  final TargetExpression left;
  final TargetOp op;
  final TargetExpression right;

  @override
  int _value(List<int> pool) {
    final a = left._value(pool);
    final b = right._value(pool);
    final result = op.apply(a, b);
    if (result == null) {
      throw FormatException(op == TargetOp.divide ? '$a ${op.ascii} $b is not exact' : '$a ${op.ascii} $b is not positive');
    }
    return result;
  }

  @override
  List<int> get numbers => [...left.numbers, ...right.numbers];

  @override
  int get _precedence => op.precedence;

  @override
  String _render(String Function(TargetOp) symbol) {
    String side(TargetExpression e, {required bool rightSide}) {
      final needs = e._precedence < _precedence ||
          (rightSide && e._precedence == _precedence && (op == TargetOp.subtract || op == TargetOp.divide));
      final inner = e._render(symbol);
      return needs ? '($inner)' : inner;
    }

    return '${side(left, rightSide: false)} ${symbol(op)} ${side(right, rightSide: true)}';
  }
}

class _Parser {
  _Parser(this.text);

  final String text;
  int pos = 0;

  bool get atEnd => pos >= text.length;
  String get peek => text[pos];

  void skipSpaces() {
    while (!atEnd && text[pos] == ' ') {
      pos++;
    }
  }

  TargetExpression expression() {
    var left = term();
    while (true) {
      skipSpaces();
      if (atEnd) return left;
      final op = TargetOp.fromChar(peek);
      if (op == null || op.precedence != 1) return left;
      pos++;
      left = TargetBinary(left, op, term());
    }
  }

  TargetExpression term() {
    var left = factor();
    while (true) {
      skipSpaces();
      if (atEnd) return left;
      final op = TargetOp.fromChar(peek);
      if (op == null || op.precedence != 2) return left;
      pos++;
      left = TargetBinary(left, op, factor());
    }
  }

  TargetExpression factor() {
    skipSpaces();
    if (atEnd) throw FormatException('Expected a number at the end of "$text"');
    if (peek == '(') {
      pos++;
      final inner = expression();
      skipSpaces();
      if (atEnd || peek != ')') throw FormatException('Missing ")" in "$text"');
      pos++;
      return inner;
    }
    final start = pos;
    while (!atEnd && text.codeUnitAt(pos) >= 0x30 && text.codeUnitAt(pos) <= 0x39) {
      pos++;
    }
    if (pos == start) throw FormatException('Unexpected "$peek" at $pos in "$text"');
    return TargetNumber(int.parse(text.substring(start, pos)));
  }
}
