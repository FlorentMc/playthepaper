import 'package:flutter_test/flutter_test.dart';
import 'package:playthepaper/engines/groups/groups.dart';

import 'fixtures.dart';

void main() {
  final puzzle = GroupsPuzzle.parse(skyPayload(), skyReveal());
  final planets = puzzle.groups[0].members;
  final metals = puzzle.groups[1].members;
  final stars = puzzle.groups[2].members;

  GroupsState pick(GroupsState state, List<String> tiles) {
    var next = state;
    for (final tile in tiles) {
      next = next.toggle(tile);
    }
    return next;
  }

  GroupsState submit(GroupsState state, List<String> tiles) => pick(state.clearSelection(), tiles).submit();

  test('starts with every tile on the board and nothing picked', () {
    final state = GroupsState.initial(puzzle);
    expect(state.remaining, puzzle.tiles);
    expect(state.selected, isEmpty);
    expect(state.found, isEmpty);
    expect(state.mistakes, 0);
    expect(state.isOver, isFalse);
    expect(state.canSubmit, isFalse);
    expect(state.points, 3);
  });

  test('picks up to four tiles and puts them down again', () {
    var state = pick(GroupsState.initial(puzzle), ['Venus', 'Mars', 'Jupiter']);
    expect(state.selected, ['Venus', 'Mars', 'Jupiter']);
    expect(state.isSelected('venus'), isTrue);
    expect(state.canSubmit, isFalse);
    state = state.toggle('Mars');
    expect(state.selected, ['Venus', 'Jupiter']);
    state = pick(state, ['Mars', 'Saturn']);
    expect(state.canSubmit, isTrue);
    final full = state.toggle('Lead');
    expect(full.selected, state.selected, reason: 'a fifth pick is ignored');
    expect(state.clearSelection().selected, isEmpty);
  });

  test('ignores a tile that is not on the board', () {
    final state = GroupsState.initial(puzzle);
    expect(identical(state.toggle('Pluto'), state), isTrue);
  });

  test('a correct submission locks the group and clears the board', () {
    final state = submit(GroupsState.initial(puzzle), planets);
    expect(state.found, [0]);
    expect(state.lastOutcome, GroupsOutcome.correct);
    expect(state.selected, isEmpty);
    expect(state.mistakes, 0);
    expect(state.remaining.length, 8);
    expect(state.remaining.any(planets.contains), isFalse);
  });

  test('a wrong submission costs a mistake and keeps the tiles', () {
    final state = submit(GroupsState.initial(puzzle), ['Venus', 'Mars', 'Lead', 'Tin']);
    expect(state.mistakes, 1);
    expect(state.found, isEmpty);
    expect(state.lastOutcome, GroupsOutcome.wrong);
    expect(state.remaining.length, GroupsPuzzle.tileCount);
    expect(state.selected.length, 4, reason: 'the picks stay so they can be adjusted');
    expect(state.points, 2);
  });

  test('says one away when three of the four belong together', () {
    final state = submit(GroupsState.initial(puzzle), ['Venus', 'Mars', 'Jupiter', 'Mercury']);
    expect(state.lastOutcome, GroupsOutcome.oneAway);
    expect(state.mistakes, 1);
  });

  test('four mistakes end the game unsolved', () {
    var state = GroupsState.initial(puzzle);
    for (var i = 0; i < GroupsState.maxMistakes; i++) {
      state = submit(state, ['Venus', 'Mars', 'Lead', 'Tin']);
    }
    expect(state.mistakes, 4);
    expect(state.isOver, isTrue);
    expect(state.isSolved, isFalse);
    expect(state.note(), 'Found 0 of 3 groups');
    expect(state.shareLines(), isEmpty);
    expect(state.points, 0);
    expect(identical(state.submit(), state), isTrue, reason: 'play is over');
    expect(identical(state.toggle('Venus'), state), isTrue);
  });

  test('finding all three groups solves the puzzle', () {
    var state = submit(GroupsState.initial(puzzle), stars);
    state = submit(state, ['Venus', 'Mars', 'Lead', 'Tin']);
    state = submit(state, metals);
    state = submit(state, planets);
    expect(state.isSolved, isTrue);
    expect(state.isOver, isTrue);
    expect(state.found, [2, 1, 0]);
    expect(state.mistakes, 1);
    expect(state.note(), 'Solved with 1 mistake');
    expect(state.shareLines(), ['🟦🟦🟦🟦', '🟨🟨🟨🟨', '🟩🟩🟩🟩']);
    expect(state.remaining, isEmpty);
  });

  test('the note counts the mistakes', () {
    var state = GroupsState.initial(puzzle);
    for (final group in [planets, metals, stars]) {
      state = submit(state, group);
    }
    expect(state.note(), 'Solved with no mistakes');
    expect(state.shareLines(), ['🟩🟩🟩🟩', '🟨🟨🟨🟨', '🟦🟦🟦🟦']);
    var two = GroupsState.initial(puzzle);
    two = submit(two, ['Venus', 'Mars', 'Lead', 'Tin']);
    two = submit(two, ['Venus', 'Mars', 'Lead', 'Copper']);
    for (final group in [planets, metals, stars]) {
      two = submit(two, group);
    }
    expect(two.note(), 'Solved with 2 mistakes');
  });

  test('shuffle reorders the same tiles and is the same on every device', () {
    final state = GroupsState.initial(puzzle);
    final once = state.shuffle();
    expect(once.remaining.toSet(), state.remaining.toSet());
    expect(once.remaining, isNot(state.remaining));
    expect(once.remaining, GroupsState.initial(puzzle).shuffle().remaining);
    expect(once.shuffle().remaining, isNot(once.remaining), reason: 'a second press moves them again');
  });

  test('shuffle keeps the picks and stops when one group is left', () {
    var state = pick(GroupsState.initial(puzzle), ['Venus', 'Mars']);
    state = state.shuffle();
    expect(state.selected, ['Venus', 'Mars']);
    var last = GroupsState.initial(puzzle);
    for (final group in [planets, metals]) {
      last = submit(last, group);
    }
    expect(last.canShuffle, isFalse);
    expect(identical(last.shuffle(), last), isTrue);
  });

  group('json', () {
    test('round trips', () {
      var state = submit(GroupsState.initial(puzzle), metals);
      state = submit(state, ['Venus', 'Mars', 'Sirius', 'Vega']);
      state = state.shuffle();
      state = pick(state.clearSelection(), ['Venus', 'Mars']);
      final restored = GroupsState.fromJson(puzzle, state.toJson());
      expect(restored.remaining, state.remaining);
      expect(restored.selected, state.selected);
      expect(restored.found, state.found);
      expect(restored.mistakes, state.mistakes);
      expect(restored.lastOutcome, isNull, reason: 'a restored game starts quiet');
    });

    test('rejects progress that does not belong to this puzzle', () {
      final good = GroupsState.initial(puzzle).toJson();
      void bad(String reason, Map<String, dynamic> json) {
        expect(() => GroupsState.fromJson(puzzle, json), throwsFormatException, reason: reason);
      }

      bad('order missing a tile', {...good, 'order': (good['order'] as List).sublist(1)});
      bad('unknown tile', {...good, 'order': [...(good['order'] as List).sublist(1), 'Pluto']});
      bad('repeated tile', {...good, 'order': [...(good['order'] as List).sublist(1), 'Mars']});
      bad('order not a list', {...good, 'order': 'Venus'});
      bad('found not a list', {...good, 'found': 3});
      bad('found out of range', {...good, 'found': [3]});
      bad('found repeated', {...good, 'found': [0, 0]});
      bad('mistakes negative', {...good, 'mistakes': -1});
      bad('mistakes too many', {...good, 'mistakes': 5});
      bad('mistakes missing', {...good, 'mistakes': null});
      bad('five picks', {...good, 'selected': (good['order'] as List).sublist(0, 5)});
      bad('picked a tile that is not in play', {...good, 'found': [0], 'order': (good['order'] as List)});
    });

    test('a found group is not on the board when restored', () {
      final state = submit(GroupsState.initial(puzzle), planets);
      final restored = GroupsState.fromJson(puzzle, state.toJson());
      expect(restored.remaining.length, 8);
      expect(restored.found, [0]);
    });
  });
}
