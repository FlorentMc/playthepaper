import 'package:daypencil/engines/correct/correct_engine.dart';
import 'package:test/test.dart';

Map<String, dynamic> payload({Map<String, dynamic>? over}) => {
      'dispatch': 'The tower opened in 1889 and stands 230 metres tall in Paris.',
      'details': ['1889', '230 metres', 'Paris'],
      'options': ['330 metres', '300 metres', '430 metres', '230 metres'],
      'evidence': [
        {'title': 'Height', 'text': 'It is 330 metres to the tip.', 'source': 'Wikipedia'},
      ],
      'maxAttempts': 3,
      ...?over,
    };

Map<String, dynamic> reveal({Map<String, dynamic>? over}) => {
      'alteredDetail': 1,
      'correctOption': 0,
      'explanation': 'The tower is 330 metres tall.',
      ...?over,
    };

void main() {
  group('CorrectPuzzle.parse', () {
    test('accepts a well-formed payload', () {
      final p = CorrectPuzzle.parse(payload());
      expect(p.details, ['1889', '230 metres', 'Paris']);
      expect(p.options.length, 4);
      expect(p.evidence.single.source, 'Wikipedia');
      expect(p.maxAttempts, 3);
    });

    test('splits the dispatch into segments in reading order', () {
      final p = CorrectPuzzle.parse(payload());
      final s = p.segments;
      expect(s.map((x) => x.text).join(), p.dispatch);
      expect(s.where((x) => x.isDetail).map((x) => x.detail), [0, 1, 2]);
      expect(s.first.text, 'The tower opened in ');
      expect(s.last.text, '.');
    });

    test('rejects a detail missing from the dispatch', () {
      expect(() => CorrectPuzzle.parse(payload(over: {'details': ['1889', 'London']})), throwsFormatException);
    });

    test('rejects a detail that occurs twice', () {
      expect(
        () => CorrectPuzzle.parse(payload(over: {
          'dispatch': 'Paris is Paris, opened in 1889.',
          'details': ['Paris', '1889'],
        })),
        throwsFormatException,
      );
    });

    test('rejects overlapping and duplicate details', () {
      expect(() => CorrectPuzzle.parse(payload(over: {'details': ['230', '230 metres']})), throwsFormatException);
      expect(() => CorrectPuzzle.parse(payload(over: {'details': ['1889', '1889']})), throwsFormatException);
    });

    test('rejects too few or duplicate options, bad evidence and attempts', () {
      expect(() => CorrectPuzzle.parse(payload(over: {'options': ['a', 'b']})), throwsFormatException);
      expect(() => CorrectPuzzle.parse(payload(over: {'options': ['a', 'b', 'a']})), throwsFormatException);
      expect(() => CorrectPuzzle.parse(payload(over: {'evidence': []})), throwsFormatException);
      expect(() => CorrectPuzzle.parse(payload(over: {'evidence': [{'title': 'x'}]})), throwsFormatException);
      expect(() => CorrectPuzzle.parse(payload(over: {'maxAttempts': 0})), throwsFormatException);
      expect(() => CorrectPuzzle.parse(payload(over: {'dispatch': ''})), throwsFormatException);
    });
  });

  group('CorrectReveal.parse', () {
    final p = CorrectPuzzle.parse(payload());

    test('accepts valid indices and builds the corrected dispatch', () {
      final r = CorrectReveal.parse(reveal(), p);
      expect(r.correctedDispatch(p), 'The tower opened in 1889 and stands 330 metres tall in Paris.');
      final fixed = r.correctedSegments(p).singleWhere((s) => s.isDetail);
      expect(fixed.text, '330 metres');
      expect(fixed.detail, 1);
    });

    test('rejects out-of-range indices', () {
      expect(() => CorrectReveal.parse(reveal(over: {'alteredDetail': 3}), p), throwsFormatException);
      expect(() => CorrectReveal.parse(reveal(over: {'alteredDetail': -1}), p), throwsFormatException);
      expect(() => CorrectReveal.parse(reveal(over: {'correctOption': 4}), p), throwsFormatException);
    });

    test('rejects a correct option equal to the altered detail', () {
      expect(() => CorrectReveal.parse(reveal(over: {'correctOption': 3}), p), throwsFormatException);
    });

    test('rejects a missing explanation', () {
      expect(() => CorrectReveal.parse(reveal(over: {'explanation': ''}), p), throwsFormatException);
    });
  });

  group('CorrectState', () {
    final p = CorrectPuzzle.parse(payload());
    final r = CorrectReveal.parse(reveal(), p);
    final start = CorrectState(puzzle: p, reveal: r);

    test('starts at step one with one attempt in use', () {
      expect(start.step, CorrectStep.findDetail);
      expect(start.status, CorrectStatus.playing);
      expect(start.attempts, 1);
      expect(start.attemptsLeft, 3);
    });

    test('wins straight through on attempt 1', () {
      final s = start.pickDetail(1).pickOption(0);
      expect(s.status, CorrectStatus.won);
      expect(s.step, CorrectStep.done);
      expect(s.attempts, 1);
    });

    test('a wrong detail uses an attempt and stays in step one', () {
      final s = start.pickDetail(0);
      expect(s.step, CorrectStep.findDetail);
      expect(s.wrongDetails, [0]);
      expect(s.attempts, 2);
      expect(s.attemptsLeft, 2);
    });

    test('wins on the last attempt after two wrong picks across both steps', () {
      final s = start.pickDetail(0).pickDetail(1).pickOption(3).pickOption(0);
      expect(s.status, CorrectStatus.won);
      expect(s.attempts, 3);
      expect(s.wrongPicks, 2);
    });

    test('loses after three wrong picks', () {
      final s = start.pickDetail(0).pickDetail(2).pickDetail(0);
      expect(s.wrongPicks, 2, reason: 'a repeated wrong pick is ignored');
      final lost = s.pickDetail(1).pickOption(1).pickOption(2);
      expect(lost.status, CorrectStatus.lost);
      expect(lost.step, CorrectStep.done);
      expect(lost.attempts, 3);
      expect(lost.attemptsLeft, 0);
      expect(lost.pickOption(0).status, CorrectStatus.lost, reason: 'no picks after the end');
    });

    test('ignores picks in the wrong step', () {
      expect(start.pickOption(0), start);
      final found = start.pickDetail(1);
      expect(found.pickDetail(0), found);
    });

    test('range-checks indices', () {
      expect(() => start.pickDetail(7), throwsRangeError);
      expect(() => start.pickDetail(1).pickOption(-1), throwsRangeError);
    });

    test('round-trips through json', () {
      final s = start.pickDetail(0).pickDetail(1).pickOption(2);
      final back = CorrectState.fromJson(s.toJson(), puzzle: p, reveal: r);
      expect(back, s);
      expect(back.step, CorrectStep.chooseRepair);
      expect(back.attempts, 3);
    });
  });
}
