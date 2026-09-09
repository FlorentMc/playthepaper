import 'package:equatable/equatable.dart';

/// One of the three groups: the tiles that belong to it, the title revealed
/// when it is found, and one sentence saying why they belong together.
///
/// [alsoFits] names tiles from the other groups that a solver could
/// reasonably read into this one. It is how the content declares its overlap,
/// and what [GroupsPuzzle.solve] works on when it proves the intended
/// grouping is the only complete one.
class GroupsGroup extends Equatable {
  const GroupsGroup({
    required this.title,
    required this.members,
    required this.explanation,
    this.alsoFits = const [],
  });

  final String title;
  final List<String> members;
  final String explanation;
  final List<String> alsoFits;

  /// Every tile this group could hold: its own four and its declared overlap.
  Set<String> get candidates => {...members, ...alsoFits};

  Map<String, dynamic> toJson() => {
        'title': title,
        'members': members,
        'explanation': explanation,
        if (alsoFits.isNotEmpty) 'alsoFits': alsoFits,
      };

  @override
  List<Object?> get props => [title, members, explanation, alsoFits];
}

/// Groups: twelve word tiles that sort into three groups of four.
///
/// Payload: `{"tiles": [12 strings, shuffled]}`.
/// Reveal: `{"groups": [{"title", "members": [4 strings], "explanation",
/// "alsoFits": [optional tiles]}, ×3]}`.
///
/// [parse] rejects: any shape error; a tile that is empty or longer than
/// [maxTileLength]; two tiles that normalise the same; a group whose title is
/// missing, repeats another title or is itself a tile; an explanation that is
/// not exactly one sentence; members that are not four of the payload tiles;
/// members that do not partition the twelve tiles; an `alsoFits` entry that
/// is not a tile or is already a member of its own group; a payload whose
/// rows of four give a group away; and content where the declared overlap
/// allows a second grouping in which all three groups are complete.
class GroupsPuzzle extends Equatable {
  const GroupsPuzzle._({required this.tiles, required this.groups});

  static const int groupCount = 3;
  static const int groupSize = 4;
  static const int tileCount = groupCount * groupSize;
  static const int columns = 4;
  static const int maxTileLength = 16;
  static const int maxTitleLength = 44;

  /// The twelve tiles in the order the player first sees them.
  final List<String> tiles;

  /// The three groups, in the order the content lists them.
  final List<GroupsGroup> groups;

  static final RegExp _sentenceEnd = RegExp(r'[.!?](\s|$)');
  static const Map<String, String> _folds = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a',
    'ç': 'c', 'ć': 'c', 'č': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ñ': 'n', 'ń': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
    'ý': 'y', 'ÿ': 'y',
    'š': 's', 'ś': 's', 'ž': 'z', 'ź': 'z', 'ż': 'z',
    'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'ð': 'd', 'þ': 'th', 'ł': 'l',
  };

  /// The form two pieces of text are compared in: lower case, trimmed,
  /// accents folded to ASCII, punctuation dropped, runs of space collapsed.
  /// `Café Müller` and `cafe muller!` are the same tile.
  static String normalise(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final folded = _folds[ch] ?? ch;
      for (final unit in folded.runes) {
        final c = String.fromCharCode(unit);
        if (RegExp(r'[a-z0-9]').hasMatch(c)) {
          buffer.write(c);
        } else {
          buffer.write(' ');
        }
      }
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// The index of the group [tile] belongs to.
  int groupOf(String tile) {
    final key = normalise(tile);
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].members.any((m) => normalise(m) == key)) return i;
    }
    throw ArgumentError('"$tile" is not a tile of this puzzle');
  }

  /// The group whose four members are exactly [selection], or null.
  int? matchFor(Iterable<String> selection) {
    final keys = selection.map(normalise).toSet();
    if (keys.length != groupSize) return null;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].members.map(normalise).toSet().difference(keys).isEmpty) return i;
    }
    return null;
  }

  /// True when exactly three of [selection] share a group, which is what the
  /// player is told after a wrong submission.
  bool isOneAway(Iterable<String> selection) {
    final keys = selection.map(normalise).toSet();
    if (keys.length != groupSize) return false;
    for (final group in groups) {
      final shared = group.members.where((m) => keys.contains(normalise(m))).length;
      if (shared == groupSize - 1) return true;
    }
    return false;
  }

  /// Every way to fill all three groups when each tile may go to any group
  /// that lists it as a member or as an `alsoFits`. Stops at [limit]
  /// solutions, which is all uniqueness needs. Each solution maps a group
  /// index to its four tiles.
  List<List<List<String>>> solve({int limit = 2}) {
    final candidates = groups.map((g) => g.candidates.map(normalise).toSet()).toList(growable: false);
    final found = <List<List<String>>>[];
    final assigned = List.generate(groupCount, (_) => <String>[], growable: false);

    void search(int index) {
      if (found.length >= limit) return;
      if (index == tiles.length) {
        found.add([for (final g in assigned) List<String>.of(g)]);
        return;
      }
      final tile = tiles[index];
      final key = normalise(tile);
      for (var g = 0; g < groupCount; g++) {
        if (assigned[g].length == groupSize || !candidates[g].contains(key)) continue;
        assigned[g].add(tile);
        search(index + 1);
        assigned[g].removeLast();
        if (found.length >= limit) return;
      }
    }

    search(0);
    return found;
  }

  static GroupsPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawTiles = payload['tiles'];
    if (rawTiles is! List || rawTiles.length != tileCount) {
      throw const FormatException('Groups payload needs exactly $tileCount "tiles"');
    }
    final tiles = <String>[];
    final byKey = <String, String>{};
    for (var i = 0; i < rawTiles.length; i++) {
      final raw = rawTiles[i];
      if (raw is! String || raw.trim().isEmpty) throw FormatException('Groups tile ${i + 1} must be a non-empty string');
      final tile = raw.trim();
      if (tile.length > maxTileLength) {
        throw FormatException('Groups tile "$tile" is longer than $maxTileLength characters');
      }
      final key = normalise(tile);
      if (key.isEmpty) throw FormatException('Groups tile "$tile" has no letters or digits');
      final clash = byKey[key];
      if (clash != null) throw FormatException('Groups tiles "$clash" and "$tile" are the same tile');
      byKey[key] = tile;
      tiles.add(tile);
    }

    final rawGroups = reveal['groups'];
    if (rawGroups is! List || rawGroups.length != groupCount) {
      throw const FormatException('Groups reveal needs exactly $groupCount "groups"');
    }
    final groups = <GroupsGroup>[];
    final titles = <String>{};
    final claimed = <String, String>{};
    for (var g = 0; g < rawGroups.length; g++) {
      final raw = rawGroups[g];
      if (raw is! Map) throw FormatException('Groups group ${g + 1} must be an object');
      final title = raw['title'];
      if (title is! String || title.trim().isEmpty) throw FormatException('Groups group ${g + 1} needs a "title"');
      if (title.trim().length > maxTitleLength) {
        throw FormatException('Groups title "$title" is longer than $maxTitleLength characters');
      }
      if (!titles.add(normalise(title))) throw FormatException('Groups title "$title" is repeated');
      if (byKey.containsKey(normalise(title))) {
        throw FormatException('Groups title "$title" is also a tile, which gives the group away');
      }
      final explanation = raw['explanation'];
      if (explanation is! String || explanation.trim().isEmpty) {
        throw FormatException('Groups group "$title" needs an "explanation"');
      }
      final sentences = _sentenceEnd.allMatches(explanation.trim()).length;
      if (sentences != 1) {
        throw FormatException('Groups explanation for "$title" must be one sentence, not $sentences');
      }
      final rawMembers = raw['members'];
      if (rawMembers is! List || rawMembers.length != groupSize || rawMembers.any((m) => m is! String)) {
        throw FormatException('Groups group "$title" needs $groupSize "members"');
      }
      final members = <String>[];
      for (final raw in rawMembers.cast<String>()) {
        final key = normalise(raw);
        final tile = byKey[key];
        if (tile == null) throw FormatException('Groups member "$raw" of "$title" is not one of the tiles');
        final owner = claimed[key];
        if (owner != null) throw FormatException('Groups tile "$tile" is in both "$owner" and "$title"');
        claimed[key] = title;
        members.add(tile);
      }
      final rawAlsoFits = raw['alsoFits'] ?? const <String>[];
      if (rawAlsoFits is! List || rawAlsoFits.any((m) => m is! String)) {
        throw FormatException('Groups "alsoFits" for "$title" must be a list of tiles');
      }
      final alsoFits = <String>[];
      for (final raw in rawAlsoFits.cast<String>()) {
        final tile = byKey[normalise(raw)];
        if (tile == null) throw FormatException('Groups "alsoFits" entry "$raw" of "$title" is not one of the tiles');
        if (members.any((m) => normalise(m) == normalise(tile))) {
          throw FormatException('Groups "alsoFits" entry "$tile" is already a member of "$title"');
        }
        if (alsoFits.any((a) => normalise(a) == normalise(tile))) {
          throw FormatException('Groups "alsoFits" entry "$tile" of "$title" is repeated');
        }
        alsoFits.add(tile);
      }
      groups.add(GroupsGroup(
        title: title.trim(),
        members: List.unmodifiable(members),
        explanation: explanation.trim(),
        alsoFits: List.unmodifiable(alsoFits),
      ));
    }
    if (claimed.length != tileCount) {
      final loose = tiles.where((t) => !claimed.containsKey(normalise(t))).join(', ');
      throw FormatException('Groups tiles are in no group: $loose');
    }

    final puzzle = GroupsPuzzle._(tiles: List.unmodifiable(tiles), groups: List.unmodifiable(groups));
    for (var row = 0; row < tileCount; row += columns) {
      if (puzzle.matchFor(tiles.sublist(row, row + columns)) != null) {
        throw FormatException('Groups row ${row ~/ columns + 1} of the payload is a whole group; shuffle the tiles');
      }
    }
    final solutions = puzzle.solve();
    if (solutions.length != 1) {
      throw const FormatException('Groups content allows a second grouping in which all three groups are complete');
    }
    return puzzle;
  }

  Map<String, dynamic> toPayload() => {'tiles': tiles};

  Map<String, dynamic> toReveal() => {'groups': groups.map((g) => g.toJson()).toList()};

  /// The same puzzle with the tiles in [order], which must be a permutation
  /// of [tiles]. Used by the generator to lay the board out by date.
  GroupsPuzzle withTiles(List<String> order) {
    final keys = order.map(normalise).toSet();
    if (order.length != tileCount || keys.length != tileCount || !keys.containsAll(tiles.map(normalise))) {
      throw const FormatException('Groups layout must be a permutation of the tiles');
    }
    return GroupsPuzzle._(tiles: List.unmodifiable(order), groups: groups);
  }

  @override
  List<Object?> get props => [tiles, groups];
}
