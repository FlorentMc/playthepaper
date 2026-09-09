import 'package:playthepaper/engines/nonogram/nonogram.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final puzzle = crossPuzzle();
  final payload = puzzle.toPayload();
  final reveal = puzzle.toReveal();

  Map<String, dynamic> withPayload(Map<String, dynamic> changes) => {...payload, ...changes};

  test('a picture yields the clues its rows and columns read', () {
    expect(puzzle.width, 5);
    expect(puzzle.height, 5);
    expect(puzzle.rows, [
      [3],
      [1],
      [5],
      [1],
      [3],
    ]);
    expect(puzzle.cols, [
      [1],
      [1, 1, 1],
      [5],
      [1, 1, 1],
      [1],
    ]);
    expect(puzzle.picture, crossPicture);
    expect(puzzle.filledCount, 13);
    expect(puzzle.fillFraction, closeTo(13 / 25, 1e-9));
    expect(puzzle.filledAt(0, 1), isTrue);
    expect(puzzle.filledAt(0, 0), isFalse);
  });

  test('parsing the payload and reveal reproduces the puzzle', () {
    final parsed = NonogramPuzzle.parse(payload, reveal);
    expect(parsed.rows, puzzle.rows);
    expect(parsed.cols, puzzle.cols);
    expect(parsed.picture, puzzle.picture);
    expect(parsed.title, 'Cross');
  });

  test('a blank line is clued as an empty list and round trips', () {
    final open = NonogramPuzzle.fromPicture(
      picture: const ['11111', '00000', '11011', '10001', '11111'],
      title: 'Frame',
    );
    expect(open.rows[1], isEmpty);
    final again = NonogramPuzzle.parse(open.toPayload(), open.toReveal());
    expect(again.picture, open.picture);
    expect(again.rows[1], isEmpty);
  });

  group('rejects', () {
    test('a missing width', () {
      expect(() => NonogramPuzzle.parse({...payload}..remove('width'), reveal), throwsFormatException);
    });

    test('a width outside the supported range', () {
      expect(() => NonogramPuzzle.parse(withPayload({'width': 2}), reveal), throwsFormatException);
      expect(() => NonogramPuzzle.parse(withPayload({'width': 21}), reveal), throwsFormatException);
    });

    test('a missing title', () {
      expect(() => NonogramPuzzle.parse({...payload}..remove('title'), reveal), throwsFormatException);
    });

    test('a blank title', () {
      expect(() => NonogramPuzzle.fromPicture(picture: crossPicture, title: '  '), throwsFormatException);
    });

    test('the wrong number of row clues', () {
      expect(
        () => NonogramPuzzle.parse(withPayload({'rows': puzzle.rows.take(4).toList()}), reveal),
        throwsFormatException,
      );
    });

    test('the wrong number of column clues', () {
      expect(
        () => NonogramPuzzle.parse(withPayload({'cols': [...puzzle.cols, <int>[1]]}), reveal),
        throwsFormatException,
      );
    });

    test('clues that are not lists of ints', () {
      expect(() => NonogramPuzzle.parse(withPayload({'rows': ['3', 1, 5, 1, 3]}), reveal), throwsFormatException);
    });

    test('a run of zero or less', () {
      expect(
        () => NonogramPuzzle.parse(withPayload({'rows': [[0], [1], [5], [1], [3]]}), reveal),
        throwsFormatException,
      );
    });

    test('a clue that cannot fit its line', () {
      expect(
        () => NonogramPuzzle.parse(withPayload({'rows': [[3, 3], [1], [5], [1], [3]]}), reveal),
        throwsFormatException,
      );
    });

    test('a clue that does not match the picture', () {
      expect(
        () => NonogramPuzzle.parse(withPayload({'rows': [[2], [1], [5], [1], [3]]}), reveal),
        throwsFormatException,
      );
    });

    test('a reveal with the wrong number of rows', () {
      expect(() => NonogramPuzzle.parse(payload, {'cells': crossPicture.take(4).toList()}), throwsFormatException);
    });

    test('a reveal row of the wrong length', () {
      expect(
        () => NonogramPuzzle.parse(payload, {'cells': ['0111', '00100', '11111', '00100', '01110']}),
        throwsFormatException,
      );
    });

    test('a reveal cell that is neither 0 nor 1', () {
      expect(
        () => NonogramPuzzle.parse(payload, {'cells': ['0x110', '00100', '11111', '00100', '01110']}),
        throwsFormatException,
      );
    });

    test('a missing reveal', () {
      expect(() => NonogramPuzzle.parse(payload, const {}), throwsFormatException);
    });

    test('clues with more than one solution', () {
      expect(
        () => NonogramPuzzle.fromPicture(
          picture: const ['10010', '00000', '01001', '00000', '00000'],
          title: 'Ambiguous',
        ),
        throwsFormatException,
      );
    });
  });
}
