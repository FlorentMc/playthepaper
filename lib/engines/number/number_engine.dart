import 'package:equatable/equatable.dart';

/// Rules for The Number: estimate a figure on a bounded slider. Scoring is
/// the percentage error of the estimate against the real figure.

Never _bad(String message) => throw FormatException('number: $message');

double _number(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is num && v.isFinite) return v.toDouble();
  return _bad('$key must be a finite number');
}

String _text(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is String && v.trim().isNotEmpty) return v;
  return _bad('$key must be a non-empty string');
}

class NumberPuzzle extends Equatable {
  const NumberPuzzle({
    required this.question,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.comparison,
  });

  final String question;
  final String unit;
  final double min;
  final double max;
  final double step;

  /// A true, related figure that anchors the estimate.
  final String comparison;

  static NumberPuzzle parse(Map<String, dynamic> payload) {
    final min = _number(payload, 'min');
    final max = _number(payload, 'max');
    final step = _number(payload, 'step');
    if (min >= max) _bad('min must be below max');
    if (step <= 0) _bad('step must be positive');
    final divisions = (max - min) / step;
    if ((divisions - divisions.round()).abs() > 1e-9 || divisions.round() < 1) {
      _bad('the range must be a whole number of steps');
    }
    return NumberPuzzle(
      question: _text(payload, 'question'),
      unit: _text(payload, 'unit'),
      min: min,
      max: max,
      step: step,
      comparison: _text(payload, 'comparison'),
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'unit': unit,
        'min': _plain(min),
        'max': _plain(max),
        'step': _plain(step),
        'comparison': comparison,
      };

  int get divisions => ((max - min) / step).round();

  /// Number of decimals needed to print a value on this scale.
  int get decimals {
    var d = 0;
    var s = step;
    while (d < 6 && (s - s.round()).abs() > 1e-9) {
      s *= 10;
      d++;
    }
    return d;
  }

  /// Nearest slider position to [value], clamped to the range.
  double snap(double value) {
    final v = value.clamp(min, max);
    final n = ((v - min) / step).round();
    final snapped = min + n * step;
    return double.parse(snapped.toStringAsFixed(decimals));
  }

  /// A value formatted for display, e.g. `330` or `2.5`.
  String format(double value) {
    final text = value.toStringAsFixed(decimals);
    final parts = text.split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    final negative = whole.startsWith('-');
    final digits = negative ? whole.substring(1) : whole;
    for (var i = 0; i < digits.length; i++) {
      final left = digits.length - i;
      buf.write(digits[i]);
      if (left > 1 && left % 3 == 1) buf.write(',');
    }
    final grouped = (negative ? '-' : '') + buf.toString();
    return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  }

  String formatWithUnit(double value) => '${format(value)} $unit';

  @override
  List<Object?> get props => [question, unit, min, max, step, comparison];
}

Object _plain(double v) => v == v.roundToDouble() ? v.round() : v;

class NumberReveal extends Equatable {
  const NumberReveal({
    required this.answer,
    required this.context,
    required this.perfectPct,
    required this.zeroPct,
  });

  final double answer;
  final String context;

  /// Error at or below which the estimate scores 100.
  final double perfectPct;

  /// Error at or above which the estimate scores 0 and counts as unsolved.
  final double zeroPct;

  static NumberReveal parse(Map<String, dynamic> reveal, NumberPuzzle puzzle) {
    final answer = _number(reveal, 'answer');
    if (answer == 0) _bad('answer must not be zero');
    if (answer < puzzle.min || answer > puzzle.max) _bad('answer must lie within the slider range');
    final scoring = reveal['scoring'];
    if (scoring is! Map) _bad('scoring must be an object');
    final s = Map<String, dynamic>.from(scoring);
    final perfect = _number(s, 'perfectPct');
    final zero = _number(s, 'zeroPct');
    if (perfect < 0 || perfect >= zero) _bad('scoring needs 0 <= perfectPct < zeroPct');
    return NumberReveal(answer: answer, context: _text(reveal, 'context'), perfectPct: perfect, zeroPct: zero);
  }

  Map<String, dynamic> toJson() => {
        'answer': _plain(answer),
        'context': context,
        'scoring': {'perfectPct': _plain(perfectPct), 'zeroPct': _plain(zeroPct)},
      };

  double errorPct(double guess) => (guess - answer).abs() / answer.abs() * 100;

  /// 100 at [perfectPct] or better, 0 at [zeroPct] or worse, linear between.
  int score(double guess) {
    final e = errorPct(guess);
    if (e <= perfectPct) return 100;
    if (e >= zeroPct) return 0;
    return (100 * (zeroPct - e) / (zeroPct - perfectPct)).round();
  }

  bool solved(double guess) => errorPct(guess) <= zeroPct;

  @override
  List<Object?> get props => [answer, context, perfectPct, zeroPct];
}

class NumberState extends Equatable {
  const NumberState({required this.value, this.submitted = false});

  final double value;
  final bool submitted;

  NumberState withValue(double v) => submitted ? this : NumberState(value: v);
  NumberState submit() => NumberState(value: value, submitted: true);

  Map<String, dynamic> toJson() => {'value': value, 'submitted': submitted};

  static NumberState fromJson(Map<String, dynamic> json) => NumberState(
        value: (json['value'] as num).toDouble(),
        submitted: json['submitted'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [value, submitted];
}
