import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/crossmatch/crossmatch.dart';

import 'fixtures.dart';

void main() {
  /// The grid in the fixture, row-major, as tile names.
  const solved = ['Naples', 'Reykjavik', 'Osaka', 'Sicily', 'Surtsey', 'Okinawa', 'Vesuvius', 'Hekla', 'Sakurajima'];

  void rejects(
    String why,
    void Function(Map<String, dynamic> payload, Map<String, dynamic> reveal) mutate, {
    required String message,
  }) {
    test('rejects $why', () {
      final payload = placesPayload();
      final reveal = placesReveal();
      mutate(payload, reveal);
      expect(
        () => CrossmatchPuzzle.parse(payload, reveal),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(message))),
      );
    });
  }

  test('parses a well-formed grid', () {
    final puzzle = CrossmatchPuzzle.parse(placesPayload(), placesReveal());
    expect(puzzle.title, 'Islands and volcanoes');
    expect(puzzle.rows, ['City', 'Island', 'Volcano']);
    expect(puzzle.cols, ['In Italy', 'In Iceland', 'In Japan']);
    expect(puzzle.tiles.length, 9);
    expect([for (var cell = 0; cell < 9; cell++) puzzle.tiles[puzzle.tileAt(cell)]], solved);
    final surtsey = puzzle.tiles.indexOf('Surtsey');
    expect(puzzle.cellOf(surtsey), CrossmatchPuzzle.cellIndex(1, 1));
    expect(puzzle.tileFits(surtsey, CrossmatchPuzzle.cellIndex(2, 1)), isTrue);
    expect(puzzle.tileFits(surtsey, CrossmatchPuzzle.cellIndex(2, 0)), isFalse);
    expect(puzzle.explanations[surtsey], contains('Iceland'));
  });

  test('the reveal round trips through toPayload and toReveal', () {
    final puzzle = CrossmatchPuzzle.parse(placesPayload(), placesReveal());
    expect(CrossmatchPuzzle.parse(puzzle.toPayload(), puzzle.toReveal()), puzzle);
  });

  test('names are compared with case, accents and punctuation folded away', () {
    expect(CrossmatchPuzzle.normalise('  São  Paulo '), 'sao paulo');
    expect(CrossmatchPuzzle.normalise('SAO-PAULO'), 'sao paulo');
    expect(CrossmatchPuzzle.normalise("Lord's"), 'lords');
    expect(CrossmatchPuzzle.normalise('U.S. Route 66'), 'us route 66');
    expect(CrossmatchPuzzle.normalise('Reykjavík'), 'reykjavik');
    expect(CrossmatchPuzzle.normalise('“Zürich”'), 'zurich');

    final payload = placesPayload();
    final reveal = placesReveal();
    (payload['tiles'] as List)[8] = 'Reykjavík';
    expect(CrossmatchPuzzle.parse(payload, reveal).tiles, contains('Reykjavík'));
  });

  rejects('a title that is not a string', (p, r) => p['title'] = 7, message: 'non-empty string');
  rejects('too few row criteria', (p, r) => p['rows'] = ['City', 'Island'], message: '"rows"');
  rejects('an empty column criterion', (p, r) => (p['cols'] as List)[1] = '  ', message: '"cols"');
  rejects('a criterion used twice', (p, r) => (p['cols'] as List)[1] = 'island', message: 'is repeated');
  rejects('the wrong number of tiles', (p, r) => (p['tiles'] as List).removeLast(), message: 'exactly 9 "tiles"');
  rejects('a tile repeated under folding', (p, r) => (p['tiles'] as List)[1] = 'HEKLA', message: 'is repeated');
  rejects('an empty tile', (p, r) => (p['tiles'] as List)[1] = ' ', message: 'non-empty strings');
  rejects('a grid that is not three by three', (p, r) => (r['grid'] as List).removeLast(), message: '3×3 "grid"');
  rejects('a grid naming something that is not a tile', (p, r) => (r['grid'] as List<dynamic>)[0][0] = 'Rome',
      message: 'not a tile');
  rejects('a grid placing one tile twice', (p, r) => (r['grid'] as List<dynamic>)[0][0] = 'Hekla', message: 'twice');
  rejects('a missing explanation', (p, r) => (r['explanations'] as Map).remove('Hekla'), message: 'no explanation');
  rejects('an empty explanation', (p, r) => (r['explanations'] as Map)['Hekla'] = '', message: 'is empty');
  rejects('an explanation for something that is not a tile',
      (p, r) => (r['explanations'] as Map)['Rome'] = 'Not a tile.', message: 'not a tile');
  rejects('an explanation given twice', (p, r) => (r['explanations'] as Map)['HEKLA'] = 'Again.', message: 'is repeated');
  rejects('missing fits', (p, r) => (r['fits'] as Map).remove('Hekla'), message: 'has no fits');
  rejects('an empty fits list', (p, r) => (r['fits'] as Map)['Hekla'] = <Object?>[], message: 'at least one cell');
  rejects('a fits entry that is not a cell', (p, r) => (r['fits'] as Map)['Hekla'] = [
        [2, 3],
      ], message: '[row, col] pairs');
  rejects('a repeated cell in fits', (p, r) => (r['fits'] as Map)['Hekla'] = [
        [2, 1],
        [2, 1],
      ], message: 'repeat a cell');
  rejects('fits that leave out the tile\'s own cell', (p, r) => (r['fits'] as Map)['Hekla'] = [
        [2, 2],
      ], message: 'does not fit the cell');
  rejects('a placement that is not the only one', (p, r) => (r['fits'] as Map)['Hekla'] = [
        [2, 1],
        [1, 1],
      ], message: 'not unique: 2 matchings');
  rejects('tiles left in their solved order', (p, r) => p['tiles'] = [...solved], message: 'not shuffled enough');

  test('accepts two tiles that happen to sit at their solved index but not three', () {
    final two = ['Naples', 'Reykjavik', 'Sakurajima', 'Osaka', 'Sicily', 'Surtsey', 'Okinawa', 'Vesuvius', 'Hekla'];
    expect(CrossmatchPuzzle.parse(placesPayload()..['tiles'] = two, placesReveal()).tiles, two);

    final three = ['Naples', 'Reykjavik', 'Osaka', 'Sakurajima', 'Sicily', 'Surtsey', 'Okinawa', 'Vesuvius', 'Hekla'];
    expect(
      () => CrossmatchPuzzle.parse(placesPayload()..['tiles'] = three, placesReveal()),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('3 already sit'))),
    );
  });
}
