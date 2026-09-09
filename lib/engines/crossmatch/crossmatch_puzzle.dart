import 'package:equatable/equatable.dart';

import 'crossmatch_solver.dart';

/// Crossmatch: a 3×3 grid whose rows and columns each carry a criterion,
/// and nine tiles that each belong in exactly one cell.
///
/// Payload: `{"title": "Countries", "rows": [3 criteria], "cols": [3 criteria],
/// "tiles": [9 strings, shuffled]}`. Reveal: `{"grid": [[3 tiles], ×3]` (row-major
/// intended placement), `"explanations": {tile: "why it fits row × column"}`,
/// `"fits": {tile: [[row, col], ...]}` listing every cell the tile satisfies,
/// filled by the author from verified facts.
///
/// Tile names in the reveal are matched to the payload tiles after
/// [normalise], so accents, case and punctuation cannot break a link.
///
/// [parse] rejects: any shape error; repeated or shared criteria; repeated
/// tiles; a grid that is not exactly the tiles; a tile with no explanation,
/// no fits, or fits that miss its own cell; a fits matrix with more than one
/// perfect matching (the placement must be unique); and a payload order
/// that leaves more than [maxInPlace] tiles at their solved index.
class CrossmatchPuzzle extends Equatable {
  const CrossmatchPuzzle._({
    required this.title,
    required this.rows,
    required this.cols,
    required this.tiles,
    required this.solution,
    required this.explanations,
    required this.fits,
  });

  static const int size = 3;
  static const int cellCount = size * size;
  static const int maxInPlace = 2;

  /// The theme, when the content names one.
  final String? title;
  final List<String> rows;
  final List<String> cols;

  /// The tiles in the shuffled payload order. Everything else refers to a
  /// tile by its index here.
  final List<String> tiles;

  /// Tile index per cell, row-major.
  final List<int> solution;

  /// Per tile, why it fits its cell.
  final List<String> explanations;

  /// Per tile, the sorted cell indices it satisfies.
  final List<List<int>> fits;

  static int cellIndex(int row, int col) => row * size + col;
  static int rowOf(int cell) => cell ~/ size;
  static int colOf(int cell) => cell % size;

  /// The tile that belongs in [cell].
  int tileAt(int cell) => solution[cell];

  /// The cell [tile] belongs in.
  int cellOf(int tile) => solution.indexOf(tile);

  bool tileFits(int tile, int cell) => fits[tile].contains(cell);

  static const Map<String, String> _folds = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ð': 'd', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'þ': 'th', 'ß': 'ss', 'œ': 'oe', 'ł': 'l', 'ś': 's', 'ş': 's',
    'š': 's', 'ż': 'z', 'ź': 'z', 'ž': 'z', 'ć': 'c', 'č': 'c', 'ř': 'r', 'ě': 'e', 'ę': 'e', 'ą': 'a', 'ğ': 'g', 'ı': 'i',
    'ń': 'n', 'ő': 'o', 'ű': 'u', 'đ': 'd', 'ṣ': 's', 'ṭ': 't', 'ā': 'a', 'ē': 'e', 'ī': 'i', 'ō': 'o', 'ū': 'u',
  };

  /// The form used to compare names: trimmed, lower-case, accents folded to
  /// ASCII, apostrophes and full stops dropped (`don't` → `dont`, `U.S.` →
  /// `us`), every other punctuation mark treated as a space, and runs of
  /// spaces collapsed. `São Paulo`, `SAO PAULO` and `Sao-Paulo` all become
  /// `sao paulo`.
  static String normalise(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final folded = _folds[ch];
      if (folded != null) {
        buffer.write(folded);
      } else if (ch == "'" || ch == '’' || ch == '.' || ch == '"' || ch == '“' || ch == '”') {
        continue;
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static CrossmatchPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawTitle = payload['title'];
    if (rawTitle != null && (rawTitle is! String || rawTitle.trim().isEmpty)) {
      throw const FormatException('Crossmatch "title" must be a non-empty string when present');
    }
    final rows = _criteria(payload['rows'], 'rows');
    final cols = _criteria(payload['cols'], 'cols');
    final keys = <String>{};
    for (final c in [...rows, ...cols]) {
      if (!keys.add(normalise(c))) throw FormatException('Crossmatch criterion "$c" is repeated');
    }

    final rawTiles = payload['tiles'];
    if (rawTiles is! List || rawTiles.length != cellCount) {
      throw const FormatException('Crossmatch payload needs exactly $cellCount "tiles"');
    }
    final tiles = <String>[];
    final tileIndex = <String, int>{};
    for (final raw in rawTiles) {
      if (raw is! String || raw.trim().isEmpty) throw const FormatException('Crossmatch tiles must be non-empty strings');
      final key = normalise(raw);
      if (key.isEmpty || tileIndex.containsKey(key)) throw FormatException('Crossmatch tile "$raw" is repeated');
      tileIndex[key] = tiles.length;
      tiles.add(raw.trim());
    }
    int tileNamed(Object? name, String where) {
      if (name is! String) throw FormatException('Crossmatch $where must name tiles');
      final index = tileIndex[normalise(name)];
      if (index == null) throw FormatException('Crossmatch $where names "$name", which is not a tile');
      return index;
    }

    final rawGrid = reveal['grid'];
    if (rawGrid is! List || rawGrid.length != size || rawGrid.any((r) => r is! List || r.length != size)) {
      throw const FormatException('Crossmatch reveal needs a $size×$size "grid"');
    }
    final solution = <int>[];
    for (final row in rawGrid) {
      for (final name in row as List) {
        final tile = tileNamed(name, 'grid');
        if (solution.contains(tile)) throw FormatException('Crossmatch grid places "$name" twice');
        solution.add(tile);
      }
    }

    final rawExplanations = reveal['explanations'];
    if (rawExplanations is! Map) throw const FormatException('Crossmatch reveal needs "explanations"');
    final explanations = List<String?>.filled(cellCount, null);
    for (final entry in rawExplanations.entries) {
      final tile = tileNamed(entry.key, 'explanations');
      final text = entry.value;
      if (text is! String || text.trim().isEmpty) throw FormatException('Crossmatch explanation for "${entry.key}" is empty');
      if (explanations[tile] != null) throw FormatException('Crossmatch explanation for "${entry.key}" is repeated');
      explanations[tile] = text;
    }
    for (var t = 0; t < cellCount; t++) {
      if (explanations[t] == null) throw FormatException('Crossmatch tile "${tiles[t]}" has no explanation');
    }

    final rawFits = reveal['fits'];
    if (rawFits is! Map) throw const FormatException('Crossmatch reveal needs "fits"');
    final fits = List<List<int>?>.filled(cellCount, null);
    for (final entry in rawFits.entries) {
      final tile = tileNamed(entry.key, 'fits');
      final raw = entry.value;
      if (raw is! List || raw.isEmpty) throw FormatException('Crossmatch fits for "${entry.key}" must list at least one cell');
      final cells = <int>{};
      for (final pair in raw) {
        if (pair is! List || pair.length != 2 || pair.any((v) => v is! int || v < 0 || v >= size)) {
          throw FormatException('Crossmatch fits for "${entry.key}" must be [row, col] pairs from 0 to ${size - 1}');
        }
        if (!cells.add(cellIndex(pair[0] as int, pair[1] as int))) {
          throw FormatException('Crossmatch fits for "${entry.key}" repeat a cell');
        }
      }
      if (fits[tile] != null) throw FormatException('Crossmatch fits for "${entry.key}" are repeated');
      fits[tile] = cells.toList()..sort();
    }
    for (var t = 0; t < cellCount; t++) {
      final cells = fits[t];
      if (cells == null) throw FormatException('Crossmatch tile "${tiles[t]}" has no fits');
      if (!cells.contains(solution.indexOf(t))) {
        throw FormatException('Crossmatch tile "${tiles[t]}" does not fit the cell the grid gives it');
      }
    }
    final matchings = CrossmatchSolver.countMatchings(fits.cast<List<int>>());
    if (matchings != 1) {
      throw FormatException('Crossmatch placement is not unique: $matchings matchings fit the criteria');
    }

    var inPlace = 0;
    for (var t = 0; t < cellCount; t++) {
      if (solution[t] == t) inPlace++;
    }
    if (inPlace > maxInPlace) {
      throw FormatException('Crossmatch tiles are not shuffled enough: $inPlace already sit at their solved index');
    }

    return CrossmatchPuzzle._(
      title: rawTitle as String?,
      rows: List.unmodifiable(rows),
      cols: List.unmodifiable(cols),
      tiles: List.unmodifiable(tiles),
      solution: List.unmodifiable(solution),
      explanations: List.unmodifiable(explanations.cast<String>()),
      fits: List.unmodifiable(fits.map((f) => List<int>.unmodifiable(f!))),
    );
  }

  static List<String> _criteria(Object? raw, String field) {
    if (raw is! List || raw.length != size || raw.any((c) => c is! String || c.trim().isEmpty)) {
      throw FormatException('Crossmatch payload needs exactly $size "$field" criteria');
    }
    return raw.cast<String>().map((c) => c.trim()).toList();
  }

  Map<String, dynamic> toPayload() => {
        if (title != null) 'title': title,
        'rows': rows,
        'cols': cols,
        'tiles': tiles,
      };

  Map<String, dynamic> toReveal() => {
        'grid': [
          for (var r = 0; r < size; r++) [for (var c = 0; c < size; c++) tiles[solution[cellIndex(r, c)]]],
        ],
        'explanations': {for (var t = 0; t < cellCount; t++) tiles[t]: explanations[t]},
        'fits': {
          for (var t = 0; t < cellCount; t++) tiles[t]: [for (final cell in fits[t]) [rowOf(cell), colOf(cell)]],
        },
      };

  @override
  List<Object?> get props => [title, rows, cols, tiles, solution, explanations, fits];
}
