/// One island: the cell it sits on and how many bridge ends it needs.
class BridgesIsland {
  const BridgesIsland({required this.row, required this.col, required this.count});

  final int row;
  final int col;
  final int count;

  Map<String, dynamic> toJson() => {'row': row, 'col': col, 'count': count};

  static BridgesIsland fromJson(Object? raw, int index) {
    if (raw is! Map) throw FormatException('Bridges island $index must be an object');
    final row = raw['row'], col = raw['col'], count = raw['count'];
    if (row is! int || col is! int || count is! int) {
      throw FormatException('Bridges island $index needs integer "row", "col" and "count"');
    }
    return BridgesIsland(row: row, col: col, count: count);
  }
}

/// Two islands that face each other along a row or column with nothing
/// between them: the only places a bridge can go.
class BridgesPair {
  const BridgesPair({
    required this.index,
    required this.a,
    required this.b,
    required this.horizontal,
    required this.crossings,
  });

  final int index;

  /// Island indices: `a` is the left island of a horizontal pair or the top
  /// island of a vertical one.
  final int a;
  final int b;
  final bool horizontal;

  /// Pairs whose line crosses this one; a bridge on both is impossible.
  final List<int> crossings;

  int other(int island) => island == a ? b : a;
}

/// Why a board is not a solution. Rules are checked in this order.
enum BridgesFault {
  /// A pair carries fewer than 0 or more than 2 bridges.
  badCount,
  crossing,
  overCount,
  underCount,
  disconnected;

  String get message => switch (this) {
        badCount => 'a pair of islands can carry at most two bridges',
        crossing => 'bridges cross',
        overCount => 'an island has too many bridges',
        underCount => 'an island has too few bridges',
        disconnected => 'the islands are not all joined together',
      };
}

/// The payload half of a puzzle: the board and its islands, with the
/// geometry every rule needs. Bridges live on [pairs]; a board is a list of
/// bridge counts, one per pair.
class BridgesLayout {
  factory BridgesLayout({required int width, required int height, required List<BridgesIsland> islands}) {
    if (width < minSize || width > maxSize || height < minSize || height > maxSize) {
      throw FormatException('Bridges board must be $minSize to $maxSize cells each way, not $width×$height');
    }
    if (islands.length < 2) throw const FormatException('Bridges needs at least two islands');
    final at = List<int>.filled(width * height, -1);
    for (var i = 0; i < islands.length; i++) {
      final island = islands[i];
      if (island.row < 0 || island.row >= height || island.col < 0 || island.col >= width) {
        throw FormatException('Bridges island $i is off the board');
      }
      if (island.count < 1 || island.count > maxCount) {
        throw FormatException('Bridges island $i needs a count from 1 to $maxCount, not ${island.count}');
      }
      final cell = island.row * width + island.col;
      if (at[cell] != -1) throw FormatException('Bridges islands ${at[cell]} and $i share a cell');
      at[cell] = i;
    }
    final specs = <_PairSpec>[];
    for (var i = 0; i < islands.length; i++) {
      final island = islands[i];
      for (var c = island.col + 1; c < width; c++) {
        final j = at[island.row * width + c];
        if (j == -1) continue;
        specs.add(_PairSpec(a: i, b: j, horizontal: true, line: island.row, from: island.col, to: c));
        break;
      }
      for (var r = island.row + 1; r < height; r++) {
        final j = at[r * width + island.col];
        if (j == -1) continue;
        specs.add(_PairSpec(a: i, b: j, horizontal: false, line: island.col, from: island.row, to: r));
        break;
      }
    }
    final crossings = List.generate(specs.length, (_) => <int>[]);
    for (var h = 0; h < specs.length; h++) {
      if (!specs[h].horizontal) continue;
      for (var v = 0; v < specs.length; v++) {
        if (specs[v].horizontal) continue;
        if (specs[h].crosses(specs[v])) {
          crossings[h].add(v);
          crossings[v].add(h);
        }
      }
    }
    final pairsOf = List.generate(islands.length, (_) => <int>[]);
    final pairs = <BridgesPair>[];
    for (var p = 0; p < specs.length; p++) {
      final spec = specs[p];
      pairs.add(BridgesPair(
        index: p,
        a: spec.a,
        b: spec.b,
        horizontal: spec.horizontal,
        crossings: List.unmodifiable(crossings[p]..sort()),
      ));
      pairsOf[spec.a].add(p);
      pairsOf[spec.b].add(p);
    }
    return BridgesLayout._(
      width: width,
      height: height,
      islands: List.unmodifiable(islands),
      pairs: List.unmodifiable(pairs),
      pairsOf: List.unmodifiable(pairsOf.map(List<int>.unmodifiable)),
      islandAt: List.unmodifiable(at),
    );
  }

  const BridgesLayout._({
    required this.width,
    required this.height,
    required this.islands,
    required this.pairs,
    required this.pairsOf,
    required List<int> islandAt,
  }) : _islandAt = islandAt;

  static const int minSize = 2;
  static const int maxSize = 30;
  static const int maxCount = 8;
  static const int maxBridges = 2;

  final int width;
  final int height;
  final List<BridgesIsland> islands;
  final List<BridgesPair> pairs;

  /// The pairs each island belongs to.
  final List<List<int>> pairsOf;
  final List<int> _islandAt;

  static BridgesLayout parse(Map<String, dynamic> payload) {
    final width = payload['width'], height = payload['height'], rawIslands = payload['islands'];
    if (width is! int || height is! int) throw const FormatException('Bridges payload needs integer "width" and "height"');
    if (rawIslands is! List) throw const FormatException('Bridges payload is missing "islands"');
    final islands = <BridgesIsland>[];
    for (var i = 0; i < rawIslands.length; i++) {
      islands.add(BridgesIsland.fromJson(rawIslands[i], i));
    }
    return BridgesLayout(width: width, height: height, islands: islands);
  }

  Map<String, dynamic> toPayload() => {
        'width': width,
        'height': height,
        'islands': islands.map((i) => i.toJson()).toList(),
      };

  /// The island on a cell, or -1.
  int islandAt(int row, int col) =>
      row < 0 || row >= height || col < 0 || col >= width ? -1 : _islandAt[row * width + col];

  /// The pair joining two islands, or null when they do not face each other.
  int? pairBetween(int a, int b) {
    for (final p in pairsOf[a]) {
      if (pairs[p].other(a) == b) return p;
    }
    return null;
  }

  /// Bridge ends reaching an island on [board].
  int load(List<int> board, int island) {
    var total = 0;
    for (final p in pairsOf[island]) {
      total += board[p];
    }
    return total;
  }

  /// Pairs carrying a bridge that crosses another bridge.
  Set<int> crossingPairs(List<int> board) {
    final result = <int>{};
    for (final pair in pairs) {
      if (board[pair.index] == 0) continue;
      for (final q in pair.crossings) {
        if (board[q] > 0) result.add(pair.index);
      }
    }
    return result;
  }

  /// True when every island can be reached from every other over the
  /// bridges on [board].
  bool isConnected(List<int> board) {
    final seen = List<bool>.filled(islands.length, false);
    final queue = <int>[0];
    seen[0] = true;
    var reached = 1;
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      for (final p in pairsOf[i]) {
        if (board[p] == 0) continue;
        final j = pairs[p].other(i);
        if (seen[j]) continue;
        seen[j] = true;
        reached++;
        queue.add(j);
      }
    }
    return reached == islands.length;
  }

  /// The first broken rule on [board], or null when it is a solution.
  BridgesFault? firstFault(List<int> board) {
    if (board.length != pairs.length) throw ArgumentError('Board must have ${pairs.length} pairs');
    if (board.any((b) => b < 0 || b > maxBridges)) return BridgesFault.badCount;
    if (crossingPairs(board).isNotEmpty) return BridgesFault.crossing;
    var under = false;
    for (var i = 0; i < islands.length; i++) {
      final load = this.load(board, i);
      if (load > islands[i].count) return BridgesFault.overCount;
      if (load < islands[i].count) under = true;
    }
    if (under) return BridgesFault.underCount;
    if (!isConnected(board)) return BridgesFault.disconnected;
    return null;
  }

  bool isSolution(List<int> board) => firstFault(board) == null;
}

class _PairSpec {
  const _PairSpec({
    required this.a,
    required this.b,
    required this.horizontal,
    required this.line,
    required this.from,
    required this.to,
  });

  final int a;
  final int b;
  final bool horizontal;

  /// The row of a horizontal pair or the column of a vertical one.
  final int line;
  final int from;
  final int to;

  /// True when this horizontal pair and the vertical [v] cross strictly
  /// between their islands.
  bool crosses(_PairSpec v) => v.from < line && line < v.to && from < v.line && v.line < to;
}
