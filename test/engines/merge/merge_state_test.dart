import 'dart:convert';

import 'package:playthepaper/engines/merge/merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// A state built straight from a board, for cases a real game would take a
/// long time to reach.
MergeState stateOf(
  List<int> tiles, {
  int score = 0,
  int moves = 0,
  int random = 1234,
  int undos = 0,
  bool keepGoing = false,
  bool finished = false,
}) =>
    MergeState.fromJson({
      'seed': 4242,
      'size': 4,
      'tiles': tiles,
      'score': score,
      'moves': moves,
      'random': random,
      'undos': undos,
      'keepGoing': keepGoing,
      'finished': finished,
    });

void main() {
  group('start', () {
    test('a game opens with two tiles, no score and no history', () {
      final state = MergeState.start(seed: 2026);
      expect(state.tiles.where((v) => v != 0).length, 2);
      expect(state.score, 0);
      expect(state.moves, 0);
      expect(state.undosUsed, 0);
      expect(state.canUndo, isFalse);
      expect(state.isSolved, isFalse);
      expect(state.isStuck, isFalse);
      expect(state.isOver, isFalse);
      expect(state.emptyCount, 14);
    });

    test('the same seed deals the same game, move for move', () {
      const moves = [
        MergeDirection.left,
        MergeDirection.up,
        MergeDirection.right,
        MergeDirection.down,
        MergeDirection.left,
        MergeDirection.up,
      ];
      var a = MergeState.start(seed: 777);
      var b = MergeState.start(seed: 777);
      var c = MergeState.start(seed: 778);
      for (final d in moves) {
        a = a.move(d);
        b = b.move(d);
        c = c.move(d);
      }
      expect(a.tiles, b.tiles);
      expect(a.score, b.score);
      expect(a.randomState, b.randomState);
      expect(a.tiles, isNot(c.tiles));
    });

    test('a puzzle opens on its own board', () {
      final puzzle = MergePuzzle(seed: 99);
      expect(MergeState.of(puzzle).tiles, puzzle.openingTiles);
    });

    test('the size is checked', () {
      expect(() => MergeState.start(seed: 1, size: 2), throwsFormatException);
    });
  });

  group('move', () {
    test('a slide that changes nothing scores nothing and spawns nothing', () {
      final state = stateOf([
        2, 4, 0, 0, //
        8, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ]);
      final next = state.move(MergeDirection.left);
      expect(identical(next, state), isTrue);
      expect(next.moves, 0);
      expect(next.tiles.where((v) => v != 0).length, 3);
      expect(next.randomState, state.randomState);
    });

    test('a real slide merges, scores and drops one new tile', () {
      final state = stateOf([
        2, 2, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ]);
      final next = state.move(MergeDirection.left);
      expect(next.tiles[0], 4);
      expect(next.score, 4);
      expect(next.moves, 1);
      expect(next.merged, {0});
      expect(next.spawned, isNotNull);
      expect(next.tiles.where((v) => v != 0).length, 2);
      expect(next.tiles[next.spawned!] == 2 || next.tiles[next.spawned!] == 4, isTrue);
    });

    test('the score is the sum of everything merged', () {
      var state = stateOf([
        2, 2, 4, 4, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ]);
      state = state.move(MergeDirection.left);
      expect(state.score, 12);
      final before = state.score;
      state = state.move(MergeDirection.right);
      expect(state.score, greaterThanOrEqualTo(before));
    });

    test('the spawn sequence follows the generator, not the board', () {
      final state = MergeState.start(seed: 31337);
      final direction = MergeDirection.values.firstWhere(
        (d) => MergeRules.slide(state.tiles, 4, d).changed,
      );
      final random = MergeRandom(state.randomState);
      final slide = MergeRules.slide(state.tiles, 4, direction);
      final expected = List<int>.of(slide.tiles);
      final at = MergeRules.spawn(expected, random);
      final next = state.move(direction);
      expect(next.tiles, expected);
      expect(next.spawned, at);
      expect(next.randomState, random.state);
    });

    test('a stuck board takes no more moves', () {
      final state = stateOf([
        2, 4, 2, 4, //
        4, 2, 4, 2, //
        2, 4, 2, 4, //
        4, 2, 4, 2, //
      ]);
      expect(state.isStuck, isTrue);
      expect(state.isOver, isTrue);
      for (final d in MergeDirection.values) {
        expect(identical(state.move(d), state), isTrue, reason: d.slug);
      }
    });

    test('a finished game takes no more moves', () {
      final state = stateOf([
        2, 2, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ]).finish();
      expect(state.isOver, isTrue);
      expect(identical(state.move(MergeDirection.left), state), isTrue);
    });
  });

  group('undo', () {
    test('one slide can be taken back, generator and all', () {
      final start = MergeState.start(seed: 5150);
      final moved = start.move(MergeDirection.left);
      final back = moved.undo();
      expect(back.tiles, start.tiles);
      expect(back.score, start.score);
      expect(back.moves, start.moves);
      expect(back.randomState, start.randomState);
      expect(back.undosUsed, 1);
      expect(back.canUndo, isFalse);
      expect(back.move(MergeDirection.left).tiles, moved.tiles, reason: 'the same tile comes back');
    });

    test('only one slide is kept', () {
      final state = MergeState.start(seed: 6161).move(MergeDirection.left).move(MergeDirection.up);
      final once = state.undo();
      expect(once.undosUsed, 1);
      expect(identical(once.undo(), once), isTrue);
    });

    test('there is nothing to take back at the start', () {
      final state = MergeState.start(seed: 1);
      expect(identical(state.undo(), state), isTrue);
      expect(state.undosUsed, 0);
    });
  });

  group('ending', () {
    test('2048 is the win and it asks the player what to do', () {
      final state = stateOf([
        1024, 1024, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ]);
      expect(state.isSolved, isFalse);
      final won = state.move(MergeDirection.left);
      expect(won.isSolved, isTrue);
      expect(won.bestTile, 2048);
      expect(won.awaitsChoice, isTrue);
      expect(won.keepPlaying().awaitsChoice, isFalse);
      expect(won.keepPlaying().isOver, isFalse);
    });

    test('a bigger tile is still a win', () {
      final state = stateOf([
        2048, 2048, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
        0, 0, 0, 0, //
      ], keepGoing: true);
      final next = state.move(MergeDirection.left);
      expect(next.bestTile, 4096);
      expect(next.isSolved, isTrue);
      expect(next.score, 4096);
    });

    test('finishing closes the board', () {
      final state = MergeState.start(seed: 8).finish();
      expect(state.finished, isTrue);
      expect(state.isOver, isTrue);
      expect(state.canUndo, isFalse);
      expect(identical(state.finish(), state), isTrue);
    });
  });

  group('json', () {
    test('a game round trips, generator state and all', () {
      var state = MergeState.start(seed: 24680);
      for (final d in [MergeDirection.up, MergeDirection.left, MergeDirection.down, MergeDirection.right]) {
        state = state.move(d);
      }
      state = state.keepPlaying();
      final copy = MergeState.fromJson(jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>);
      expect(copy.seed, state.seed);
      expect(copy.size, state.size);
      expect(copy.tiles, state.tiles);
      expect(copy.score, state.score);
      expect(copy.moves, state.moves);
      expect(copy.randomState, state.randomState);
      expect(copy.undosUsed, state.undosUsed);
      expect(copy.keepGoing, state.keepGoing);
      expect(copy.finished, state.finished);
      expect(copy.spawned, state.spawned);
      expect(copy.merged, state.merged);
      expect(copy.canUndo, state.canUndo);
      expect(copy.move(MergeDirection.up).tiles, state.move(MergeDirection.up).tiles);
      expect(copy.undo().tiles, state.undo().tiles);
      expect(copy.undo().randomState, state.undo().randomState);
    });

    test('a restored game plays on exactly as it would have', () {
      var live = MergeState.start(seed: 13579);
      var saved = live;
      for (var i = 0; i < 12; i++) {
        final d = MergeDirection.values[i % 4];
        live = live.move(d);
        saved = MergeState.fromJson(jsonDecode(jsonEncode(saved.move(d).toJson())) as Map<String, dynamic>);
        expect(saved.tiles, live.tiles, reason: 'move $i');
        expect(saved.score, live.score, reason: 'move $i');
      }
    });

    test('a malformed save is rejected', () {
      Map<String, dynamic> good() => stateOf([
            2, 0, 0, 0, //
            0, 0, 0, 0, //
            0, 0, 0, 0, //
            0, 0, 0, 0, //
          ]).toJson();
      void reject(String field, Object? value) {
        final json = good()..[field] = value;
        expect(() => MergeState.fromJson(json), throwsFormatException, reason: '$field = $value');
      }

      MergeState.fromJson(good());
      reject('size', '4');
      reject('size', 2);
      reject('seed', 0);
      reject('seed', 0x100000000);
      reject('tiles', [1, 2, 3]);
      reject('tiles', List<int>.filled(16, 3));
      reject('tiles', List<int>.filled(16, 1));
      reject('score', -1);
      reject('moves', 'many');
      reject('undos', -2);
      reject('random', 0);
      reject('random', 0x100000000);
      reject('spawned', 16);
      reject('spawned', -1);
      reject('merged', 16);
      reject('merged', [99]);
      reject('previous', 'nothing');
      reject('previous', {'tiles': List<int>.filled(16, 0), 'score': 0, 'moves': 0, 'random': 0});
    });
  });
}
