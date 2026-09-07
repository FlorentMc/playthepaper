import 'package:daypencil/engines/number/number_engine.dart';
import 'package:test/test.dart';

Map<String, dynamic> payload({Map<String, dynamic>? over}) => {
      'question': 'How tall is the Eiffel Tower, to the tip?',
      'unit': 'metres',
      'min': 100,
      'max': 600,
      'step': 1,
      'comparison': 'The Shard in London is 310 metres.',
      ...?over,
    };

Map<String, dynamic> reveal({Map<String, dynamic>? over}) => {
      'answer': 330,
      'context': 'Including its antennas.',
      'scoring': {'perfectPct': 2, 'zeroPct': 50},
      ...?over,
    };

void main() {
  group('NumberPuzzle.parse', () {
    test('accepts a well-formed payload', () {
      final p = NumberPuzzle.parse(payload());
      expect(p.min, 100);
      expect(p.max, 600);
      expect(p.divisions, 500);
      expect(p.decimals, 0);
    });

    test('rejects a bad range or step', () {
      expect(() => NumberPuzzle.parse(payload(over: {'min': 600})), throwsFormatException);
      expect(() => NumberPuzzle.parse(payload(over: {'step': 0})), throwsFormatException);
      expect(() => NumberPuzzle.parse(payload(over: {'step': -1})), throwsFormatException);
      expect(() => NumberPuzzle.parse(payload(over: {'step': 7})), throwsFormatException);
      expect(() => NumberPuzzle.parse(payload(over: {'unit': ''})), throwsFormatException);
    });

    test('snaps and formats values', () {
      final p = NumberPuzzle.parse(payload(over: {'min': 0, 'max': 10, 'step': 0.5}));
      expect(p.decimals, 1);
      expect(p.snap(3.3), 3.5);
      expect(p.snap(-4), 0);
      expect(p.snap(99), 10);
      expect(p.format(3.5), '3.5');
      final big = NumberPuzzle.parse(payload(over: {'min': 0, 'max': 2000000, 'step': 1000}));
      expect(big.format(1234000), '1,234,000');
      expect(big.formatWithUnit(500), '500 metres');
    });
  });

  group('NumberReveal', () {
    final p = NumberPuzzle.parse(payload());

    test('validates the answer and scoring', () {
      expect(NumberReveal.parse(reveal(), p).answer, 330);
      expect(() => NumberReveal.parse(reveal(over: {'answer': 50}), p), throwsFormatException);
      expect(() => NumberReveal.parse(reveal(over: {'answer': 601}), p), throwsFormatException);
      expect(() => NumberReveal.parse(reveal(over: {'scoring': {'perfectPct': 50, 'zeroPct': 50}}), p),
          throwsFormatException);
      expect(() => NumberReveal.parse(reveal(over: {'scoring': {'perfectPct': -1, 'zeroPct': 50}}), p),
          throwsFormatException);
      expect(() => NumberReveal.parse(reveal(over: {'context': ''}), p), throwsFormatException);
    });

    test('error percentage', () {
      final r = NumberReveal.parse(reveal(), p);
      expect(r.errorPct(330), 0);
      expect(r.errorPct(363), closeTo(10, 1e-9));
      expect(r.errorPct(297), closeTo(10, 1e-9));
    });

    test('score is linear between the perfect and zero bands', () {
      final r = NumberReveal.parse(reveal(), p);
      expect(r.score(330), 100);
      expect(r.score(336), 100, reason: '1.8% is within perfectPct');
      expect(r.score(495), 0, reason: '50% off scores zero');
      expect(r.score(600), 0);
      expect(r.score(330 * 1.26), 50);
      expect(r.score(330 * 0.74), 50);
    });

    test('solved at or below zeroPct', () {
      final r = NumberReveal.parse(reveal(), p);
      expect(r.solved(495), isTrue);
      expect(r.solved(496), isFalse);
      expect(r.solved(165), isTrue);
      expect(r.solved(164), isFalse);
    });
  });

  test('NumberState round-trips and locks after submit', () {
    const s = NumberState(value: 250);
    expect(s.withValue(300).value, 300);
    final done = s.submit();
    expect(done.submitted, isTrue);
    expect(done.withValue(1), done);
    expect(NumberState.fromJson(done.toJson()), done);
  });
}
