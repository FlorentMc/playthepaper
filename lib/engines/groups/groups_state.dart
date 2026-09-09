import 'package:equatable/equatable.dart';

import 'groups_puzzle.dart';

/// What a submission turned out to be. [oneAway] is a wrong submission in
/// which exactly three tiles shared a group.
enum GroupsOutcome { correct, oneAway, wrong }

/// The board between submissions: the tiles still in play and their order,
/// the current selection, the groups found so far in the order they were
/// found, and the mistakes spent. Immutable; every transition returns a new
/// state.
class GroupsState extends Equatable {
  const GroupsState._({
    required this.puzzle,
    required this.remaining,
    required this.selected,
    required this.found,
    required this.mistakes,
    this.lastOutcome,
  });

  GroupsState.initial(GroupsPuzzle puzzle)
      : this._(
          puzzle: puzzle,
          remaining: puzzle.tiles,
          selected: const [],
          found: const [],
          mistakes: 0,
        );

  static const int maxMistakes = 4;

  final GroupsPuzzle puzzle;

  /// The tiles still on the board, in the order they are shown.
  final List<String> remaining;

  /// The tiles the player has picked, at most [GroupsPuzzle.groupSize].
  final List<String> selected;

  /// Group indices in the order they were found.
  final List<int> found;
  final int mistakes;

  /// How the last submission went, for the message under the board. Not part
  /// of saved progress: a restored game starts quiet.
  final GroupsOutcome? lastOutcome;

  bool get isSolved => found.length == GroupsPuzzle.groupCount;

  bool get isOver => isSolved || mistakes >= maxMistakes;

  int get mistakesLeft => maxMistakes - mistakes;

  bool get canSubmit => !isOver && selected.length == GroupsPuzzle.groupSize;

  bool get canShuffle => !isOver && remaining.length > GroupsPuzzle.groupSize;

  bool isSelected(String tile) => selected.any((t) => GroupsPuzzle.normalise(t) == GroupsPuzzle.normalise(tile));

  /// Group indices still to be found, in the content's own order.
  List<int> get missing =>
      [for (var i = 0; i < GroupsPuzzle.groupCount; i++) if (!found.contains(i)) i];

  /// A display score of three points less one per mistake, never below zero.
  int get points => (GroupsPuzzle.groupCount - mistakes).clamp(0, GroupsPuzzle.groupCount);

  /// Picks a tile up or puts it down. A fifth pick is ignored.
  GroupsState toggle(String tile) {
    if (isOver || !remaining.any((t) => GroupsPuzzle.normalise(t) == GroupsPuzzle.normalise(tile))) return this;
    final key = GroupsPuzzle.normalise(tile);
    final next = List<String>.of(selected);
    final at = next.indexWhere((t) => GroupsPuzzle.normalise(t) == key);
    if (at >= 0) {
      next.removeAt(at);
    } else {
      if (next.length == GroupsPuzzle.groupSize) return this;
      next.add(remaining.firstWhere((t) => GroupsPuzzle.normalise(t) == key));
    }
    return _copy(selected: next, clearOutcome: true);
  }

  GroupsState clearSelection() => selected.isEmpty ? this : _copy(selected: const [], clearOutcome: true);

  /// Reorders the tiles still in play. The new order is derived from the
  /// current one, so a restored game shuffles the same way it would have.
  GroupsState shuffle() {
    if (!canShuffle) return this;
    var order = _shuffled(remaining, _seed(remaining));
    if (_sameOrder(order, remaining)) {
      order = [...order.sublist(1), order.first];
    }
    return _copy(remaining: order, clearOutcome: true);
  }

  /// Checks the four picked tiles. A correct set locks its group and leaves
  /// the board; a wrong one costs a mistake.
  GroupsState submit() {
    if (!canSubmit) return this;
    final match = puzzle.matchFor(selected);
    if (match == null) {
      return _copy(
        selected: selected,
        mistakes: mistakes + 1,
        outcome: puzzle.isOneAway(selected) ? GroupsOutcome.oneAway : GroupsOutcome.wrong,
      );
    }
    final keys = selected.map(GroupsPuzzle.normalise).toSet();
    return _copy(
      remaining: remaining.where((t) => !keys.contains(GroupsPuzzle.normalise(t))).toList(),
      selected: const [],
      found: [...found, match],
      outcome: GroupsOutcome.correct,
    );
  }

  /// One row of four squares per group found, in the order they were found.
  /// The colour stands for the group, never for how hard it was.
  List<String> shareLines() => [
        for (final index in found) _marks[index] * GroupsPuzzle.groupSize,
      ];

  static const List<String> _marks = ['🟩', '🟨', '🟦'];

  /// The mark shown beside a group's title, so the colour is never alone.
  static String markFor(int group) => _marks[group];

  /// The line the result screen shows verbatim.
  String note() {
    if (!isSolved) return 'Found ${found.length} of ${GroupsPuzzle.groupCount} groups';
    if (mistakes == 0) return 'Solved with no mistakes';
    return 'Solved with $mistakes mistake${mistakes == 1 ? '' : 's'}';
  }

  Map<String, dynamic> toJson() => {
        'order': remaining,
        'selected': selected,
        'found': found,
        'mistakes': mistakes,
      };

  /// Restores saved progress for [puzzle]. Throws [FormatException] when the
  /// data is malformed or does not belong to this puzzle.
  static GroupsState fromJson(GroupsPuzzle puzzle, Map<String, dynamic> json) {
    final rawFound = json['found'];
    if (rawFound is! List || rawFound.length > GroupsPuzzle.groupCount) {
      throw const FormatException('Groups progress "found" must list the groups found');
    }
    final found = <int>[];
    for (final raw in rawFound) {
      if (raw is! int || raw < 0 || raw >= GroupsPuzzle.groupCount || found.contains(raw)) {
        throw const FormatException('Groups progress "found" is not a list of distinct group numbers');
      }
      found.add(raw);
    }
    final expected = {
      for (var i = 0; i < GroupsPuzzle.groupCount; i++)
        if (!found.contains(i)) ...puzzle.groups[i].members.map(GroupsPuzzle.normalise),
    };
    List<String> tiles(Object? raw, String field, {required int max}) {
      if (raw is! List || raw.length > max || raw.any((t) => t is! String)) {
        throw FormatException('Groups progress "$field" must be a list of at most $max tiles');
      }
      final list = raw.cast<String>().toList();
      final keys = list.map(GroupsPuzzle.normalise).toSet();
      if (keys.length != list.length || !expected.containsAll(keys)) {
        throw FormatException('Groups progress "$field" does not match the tiles still in play');
      }
      return List.unmodifiable(list);
    }

    final remaining = tiles(json['order'], 'order', max: GroupsPuzzle.tileCount);
    if (remaining.length != expected.length) {
      throw const FormatException('Groups progress "order" is missing tiles that are still in play');
    }
    final selected = tiles(json['selected'] ?? const [], 'selected', max: GroupsPuzzle.groupSize);
    final mistakes = json['mistakes'];
    if (mistakes is! int || mistakes < 0 || mistakes > maxMistakes) {
      throw const FormatException('Groups progress "mistakes" is out of range');
    }
    return GroupsState._(
      puzzle: puzzle,
      remaining: remaining,
      selected: selected,
      found: List.unmodifiable(found),
      mistakes: mistakes,
    );
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _seed(List<String> order) {
    var hash = 0x811C9DC5;
    for (final unit in order.join('|').codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Fisher-Yates with a small linear congruential generator, so the same
  /// board always shuffles the same way on every device.
  static List<String> _shuffled(List<String> items, int seed) {
    final out = List<String>.of(items);
    var state = seed == 0 ? 1 : seed;
    for (var i = out.length - 1; i > 0; i--) {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      final j = state % (i + 1);
      final tmp = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }

  GroupsState _copy({
    List<String>? remaining,
    List<String>? selected,
    List<int>? found,
    int? mistakes,
    GroupsOutcome? outcome,
    bool clearOutcome = false,
  }) =>
      GroupsState._(
        puzzle: puzzle,
        remaining: remaining == null ? this.remaining : List.unmodifiable(remaining),
        selected: selected == null ? this.selected : List.unmodifiable(selected),
        found: found == null ? this.found : List.unmodifiable(found),
        mistakes: mistakes ?? this.mistakes,
        lastOutcome: clearOutcome ? null : (outcome ?? lastOutcome),
      );

  @override
  List<Object?> get props => [puzzle, remaining, selected, found, mistakes, lastOutcome];
}
