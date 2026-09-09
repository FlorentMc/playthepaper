import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/chronology/chronology.dart';

import 'fixtures.dart';

void main() {
  Map<String, dynamic> payload([void Function(Map<String, dynamic>)? edit]) {
    final p = flightPayload();
    edit?.call(p);
    return p;
  }

  Map<String, dynamic> reveal([void Function(Map<String, dynamic>)? edit]) {
    final r = flightReveal();
    edit?.call(r);
    return r;
  }

  void expectRejected(Map<String, dynamic> p, Map<String, dynamic> r, Pattern message) {
    expect(
      () => ChronologyPuzzle.parse(p, r),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(message))),
    );
  }

  test('parses a valid puzzle', () {
    final puzzle = ChronologyPuzzle.parse(payload(), reveal());
    expect(puzzle.title, 'Milestones of flight');
    expect(puzzle.eventIds, ['b', 'd', 'a', 'c']);
    expect(puzzle.order, ['a', 'b', 'c', 'd']);
    expect(puzzle.years, {'a': 1903, 'b': 1927, 'c': 1939, 'd': 1969});
    expect(puzzle.dates['d'], '1969');
    expect(puzzle.positionOf('c'), 2);
    expect(puzzle.eventById('d').text, 'Concorde makes its first flight');
    expect(ChronologyPuzzle.parse(puzzle.toPayload(), puzzle.toReveal()), puzzle);
  });

  test('title is optional but must be a non-empty string when present', () {
    expect(ChronologyPuzzle.parse(payload((p) => p.remove('title')), reveal()).title, isNull);
    expectRejected(payload((p) => p['title'] = ''), reveal(), 'title');
    expectRejected(payload((p) => p['title'] = 3), reveal(), 'title');
  });

  test('years parse, including BC, and reject anything else', () {
    expect(ChronologyPuzzle.yearOf('1969'), 1969);
    expect(ChronologyPuzzle.yearOf(' 79 '), 79);
    expect(ChronologyPuzzle.yearOf('44 BC'), -44);
    expect(ChronologyPuzzle.yearOf('300 BCE'), -300);
    expect(() => ChronologyPuzzle.yearOf('1969-07-20'), throwsFormatException);
    expect(() => ChronologyPuzzle.yearOf('c. 1500'), throwsFormatException);
    expect(() => ChronologyPuzzle.yearOf('0'), throwsFormatException);
    expect(() => ChronologyPuzzle.yearOf(''), throwsFormatException);
  });

  test('rejects the wrong number of events or malformed events', () {
    expectRejected(payload((p) => (p['events'] as List).removeLast()), reveal(), 'exactly 4');
    expectRejected(payload((p) => p.remove('events')), reveal(), 'exactly 4');
    expectRejected(payload((p) => (p['events'] as List)[0] = 'text'), reveal(), 'must be an object');
    expectRejected(payload((p) => (p['events'] as List)[1] = {'id': 'd'}), reveal(), 'needs a "text"');
    expectRejected(payload((p) => (p['events'] as List)[1] = {'text': 'x'}), reveal(), 'needs an "id"');
    expectRejected(payload((p) => (p['events'] as List)[1] = {'id': 'd', 'text': '  '}), reveal(), 'needs a "text"');
  });

  test('rejects repeated ids and repeated texts', () {
    expectRejected(payload((p) => (p['events'] as List)[1]['id'] = 'b'), reveal(), 'repeated');
    expectRejected(
      payload((p) => (p['events'] as List)[1]['text'] = 'charles lindbergh flies solo across the atlantic '),
      reveal(),
      'text is repeated',
    );
  });

  test('rejects an order that is not a permutation of the ids', () {
    expectRejected(payload(), reveal((r) => r['order'] = ['a', 'b', 'c']), 'order');
    expectRejected(payload(), reveal((r) => r['order'] = ['a', 'b', 'c', 'c']), 'exactly once');
    expectRejected(payload(), reveal((r) => r['order'] = ['a', 'b', 'c', 'e']), 'exactly once');
    expectRejected(payload(), reveal((r) => r.remove('order')), 'order');
  });

  test('rejects missing, extra or malformed dates', () {
    expectRejected(payload(), reveal((r) => r.remove('dates')), 'dates');
    expectRejected(payload(), reveal((r) => (r['dates'] as Map).remove('c')), 'missing event "c"');
    expectRejected(payload(), reveal((r) => (r['dates'] as Map)['e'] = '1990'), 'exactly one date per event');
    expectRejected(payload(), reveal((r) => (r['dates'] as Map)['c'] = 1939), 'missing event "c"');
    expectRejected(payload(), reveal((r) => (r['dates'] as Map)['c'] = 'c. 1939'), 'must be a year');
  });

  test('rejects two events in the same year', () {
    expectRejected(payload(), reveal((r) => (r['dates'] as Map)['c'] = '1927'), 'different years');
  });

  test('rejects an order that is not earliest first', () {
    expectRejected(payload(), reveal((r) => r['order'] = ['a', 'c', 'b', 'd']), 'not earliest first');
    expectRejected(payload(), reveal((r) => r['order'] = ['d', 'c', 'b', 'a']), 'not earliest first');
  });

  test('rejects an event text that gives away a year', () {
    expectRejected(
      payload((p) => (p['events'] as List)[1]['text'] = 'Concorde first flies in 1969'),
      reveal(),
      'gives away the year 1969',
    );
    expectRejected(
      payload((p) => (p['events'] as List)[1]['text'] = 'Concorde flies, unlike the 1903 Flyer'),
      reveal(),
      'gives away the year 1903',
    );
    final ok = ChronologyPuzzle.parse(
      payload((p) => (p['events'] as List)[1]['text'] = 'The Boeing 747 and Concorde fly within weeks'),
      reveal(),
    );
    expect(ok.events[1].text, contains('747'));
  });

  test('rejects a payload that leaves an event in its correct place', () {
    final events = flightPayload()['events'] as List;
    expectRejected(payload((p) => p['events'] = [events[2], events[0], events[3], events[1]]), reveal(), 'already in its correct place');
    expectRejected(payload((p) => p['events'] = [events[2], events[3], events[1], events[0]]), reveal(), 'already in its correct place');
  });

  test('rejects a missing explanation', () {
    expectRejected(payload(), reveal((r) => r.remove('explanation')), 'explanation');
    expectRejected(payload(), reveal((r) => r['explanation'] = ' '), 'explanation');
  });
}
