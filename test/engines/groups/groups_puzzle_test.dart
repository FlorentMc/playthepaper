import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/groups/groups.dart';

import 'fixtures.dart';

Map<String, dynamic> _copy(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// The reveal with one edit applied to group [index].
Map<String, dynamic> _reveal(int index, Map<String, Object?> changes) {
  final reveal = _copy(skyReveal());
  final group = (reveal['groups'] as List)[index] as Map<String, dynamic>;
  for (final entry in changes.entries) {
    if (entry.value == null) {
      group.remove(entry.key);
    } else {
      group[entry.key] = entry.value;
    }
  }
  return reveal;
}

Map<String, dynamic> _tiles(List<Object?> tiles) => {'tiles': tiles};

void main() {
  final puzzle = GroupsPuzzle.parse(skyPayload(), skyReveal());

  void rejects(String reason, Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    expect(() => GroupsPuzzle.parse(payload, reveal), throwsFormatException, reason: reason);
  }

  group('parse', () {
    test('reads the tiles and the three groups', () {
      expect(puzzle.tiles.length, GroupsPuzzle.tileCount);
      expect(puzzle.tiles.first, 'Venus');
      expect(puzzle.groups.map((g) => g.title), ['Planets', 'Metals known to the ancients', 'Bright stars']);
      expect(puzzle.groups[0].alsoFits, ['Mercury']);
      expect(puzzle.groups[1].alsoFits, isEmpty);
      expect(puzzle.groupOf('Jupiter'), 0);
      expect(puzzle.groupOf('tin'), 1);
      expect(() => puzzle.groupOf('Pluto'), throwsArgumentError);
    });

    test('round trips through payload and reveal', () {
      final again = GroupsPuzzle.parse(puzzle.toPayload(), puzzle.toReveal());
      expect(again, puzzle);
    });

    test('rejects a payload without twelve tiles', () {
      rejects('missing tiles', const {}, skyReveal());
      rejects('eleven tiles', _tiles(skyPayload()['tiles'] as List..removeLast()), skyReveal());
      rejects('tiles not a list', const {'tiles': 'Venus'}, skyReveal());
    });

    test('rejects an empty, over-long or repeated tile', () {
      final tiles = (skyPayload()['tiles'] as List).toList();
      rejects('empty tile', _tiles([...tiles.sublist(1), '  ']), skyReveal());
      rejects('not a string', _tiles([...tiles.sublist(1), 7]), skyReveal());
      rejects('too long', _tiles([...tiles.sublist(1), 'Proxima Centauri b']), skyReveal());
      rejects('repeat', _tiles(tiles.toList()..[11] = 'venus!'), skyReveal());
    });

    test('rejects a tile with no letters or digits', () {
      final tiles = (skyPayload()['tiles'] as List).toList()..[3] = '—';
      rejects('punctuation only', _tiles(tiles), skyReveal());
    });

    test('rejects the wrong number of groups', () {
      final two = _copy(skyReveal());
      (two['groups'] as List).removeLast();
      rejects('two groups', skyPayload(), two);
      rejects('groups missing', skyPayload(), const {});
    });

    test('rejects a bad title', () {
      rejects('no title', skyPayload(), _reveal(0, {'title': null}));
      rejects('empty title', skyPayload(), _reveal(0, {'title': '  '}));
      rejects('repeated title', skyPayload(), _reveal(2, {'title': 'Planets'}));
      rejects('title is a tile', skyPayload(), _reveal(2, {'title': 'Vega'}));
      rejects('title too long', skyPayload(), _reveal(2, {'title': 'Stars that are bright enough to see from a city street'}));
    });

    test('rejects an explanation that is not one sentence', () {
      rejects('no explanation', skyPayload(), _reveal(1, {'explanation': null}));
      rejects('two sentences', skyPayload(), _reveal(1, {'explanation': 'Smiths worked these. They are old metals.'}));
      rejects('no full stop', skyPayload(), _reveal(1, {'explanation': 'Smiths worked all four of these metals'}));
    });

    test('rejects members that are not four of the tiles', () {
      rejects('three members', skyPayload(), _reveal(0, {'members': ['Venus', 'Mars', 'Jupiter']}));
      rejects('unknown member', skyPayload(), _reveal(0, {'members': ['Venus', 'Mars', 'Jupiter', 'Pluto']}));
      rejects('member not a string', skyPayload(), _reveal(0, {'members': ['Venus', 'Mars', 'Jupiter', 3]}));
    });

    test('rejects members that do not partition the tiles', () {
      final reveal = _reveal(2, {'members': ['Sirius', 'Vega', 'Rigel', 'Venus']});
      rejects('Venus claimed twice and Altair loose', skyPayload(), reveal);
    });

    test('rejects a bad alsoFits', () {
      rejects('not a tile', skyPayload(), _reveal(0, {'alsoFits': ['Pluto']}));
      rejects('own member', skyPayload(), _reveal(0, {'alsoFits': ['Mars']}));
      rejects('repeated', skyPayload(), _reveal(0, {'alsoFits': ['Mercury', 'mercury']}));
      rejects('not a list', skyPayload(), _reveal(0, {'alsoFits': 'Mercury'}));
    });

    test('rejects a payload row that is a whole group', () {
      rejects('first row gives the planets away', orderedPayload(), skyReveal());
    });

    test('rejects content that allows a second complete grouping', () {
      final reveal = _copy(skyReveal());
      final groups = reveal['groups'] as List;
      (groups[0] as Map<String, dynamic>)['alsoFits'] = ['Mercury', 'Lead'];
      (groups[1] as Map<String, dynamic>)['alsoFits'] = ['Venus', 'Mars'];
      rejects('Venus and Mercury could swap', skyPayload(), reveal);
    });
  });

  group('solver', () {
    test('finds exactly the intended grouping', () {
      final solutions = puzzle.solve(limit: 5);
      expect(solutions.length, 1);
      expect(solutions.single[0].toSet(), {'Venus', 'Mars', 'Jupiter', 'Saturn'});
      expect(solutions.single[1].toSet(), {'Mercury', 'Lead', 'Tin', 'Copper'});
      expect(solutions.single[2].toSet(), {'Sirius', 'Vega', 'Rigel', 'Altair'});
    });

    test('stops at the limit', () {
      expect(puzzle.solve(limit: 1).length, 1);
    });
  });

  group('matching', () {
    test('recognises a group whatever the order or case', () {
      expect(puzzle.matchFor(['saturn', 'JUPITER', 'Mars', 'Venus']), 0);
      expect(puzzle.matchFor(['Mercury', 'Lead', 'Tin', 'Copper']), 1);
      expect(puzzle.matchFor(['Venus', 'Mars', 'Jupiter', 'Mercury']), isNull);
      expect(puzzle.matchFor(['Venus', 'Mars', 'Jupiter']), isNull);
    });

    test('spots a selection that is one away', () {
      expect(puzzle.isOneAway(['Venus', 'Mars', 'Jupiter', 'Mercury']), isTrue);
      expect(puzzle.isOneAway(['Venus', 'Mars', 'Lead', 'Tin']), isFalse);
      expect(puzzle.isOneAway(['Venus', 'Mars', 'Jupiter', 'Saturn']), isFalse, reason: 'a correct group is not one away');
    });
  });

  group('normalise', () {
    test('lower-cases, folds accents, drops punctuation and collapses spaces', () {
      expect(GroupsPuzzle.normalise('  Café   Müller!  '), 'cafe muller');
      expect(GroupsPuzzle.normalise("d'Artagnan"), 'd artagnan');
      expect(GroupsPuzzle.normalise('COMTÉ'), 'comte');
      expect(GroupsPuzzle.normalise('Straße'), 'strasse');
      expect(GroupsPuzzle.normalise('La Bohème'), 'la boheme');
      expect(GroupsPuzzle.normalise('K2'), 'k2');
    });
  });

  group('withTiles', () {
    test('lays the same puzzle out in another order', () {
      final order = puzzle.tiles.reversed.toList();
      final laid = puzzle.withTiles(order);
      expect(laid.tiles, order);
      expect(laid.groups, puzzle.groups);
    });

    test('rejects an order that is not a permutation', () {
      expect(() => puzzle.withTiles(puzzle.tiles.sublist(1)), throwsFormatException);
      final wrong = puzzle.tiles.toList()..[0] = 'Pluto';
      expect(() => puzzle.withTiles(wrong), throwsFormatException);
    });
  });
}
