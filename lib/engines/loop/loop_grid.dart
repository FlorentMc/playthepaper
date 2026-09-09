/// Geometry of a Slitherlink board: `width × height` cells, `(height + 1) ×
/// (width + 1)` dots and the edges between them.
///
/// Edges are numbered with the horizontal ones first, row-major: horizontal
/// edge `(r, c)` for `r` in `0..height` and `c` in `0..width - 1` is the top
/// side of cell `(r, c)`; vertical edge `(r, c)` for `r` in `0..height - 1`
/// and `c` in `0..width` is the left side of cell `(r, c)`. Dots and cells
/// are row-major too.
class LoopGrid {
  LoopGrid(this.width, this.height)
      : hCount = (height + 1) * width,
        vCount = height * (width + 1) {
    if (width < minSize || width > maxSize || height < minSize || height > maxSize) {
      throw FormatException('Loop grids are $minSize to $maxSize cells a side, not $width×$height');
    }
    for (var cell = 0; cell < cellCount; cell++) {
      final r = cell ~/ width, c = cell % width;
      cellEdges.add(List.unmodifiable([h(r, c), h(r + 1, c), v(r, c), v(r, c + 1)]));
    }
    for (var dot = 0; dot < dotCount; dot++) {
      final r = dot ~/ (width + 1), c = dot % (width + 1);
      dotEdges.add(List.unmodifiable([
        if (c > 0) h(r, c - 1),
        if (c < width) h(r, c),
        if (r > 0) v(r - 1, c),
        if (r < height) v(r, c),
      ]));
    }
    for (var edge = 0; edge < edgeCount; edge++) {
      if (edge < hCount) {
        final r = edge ~/ width, c = edge % width;
        edgeDots.add(List.unmodifiable([dot(r, c), dot(r, c + 1)]));
        edgeCells.add(List.unmodifiable([if (r > 0) cell(r - 1, c), if (r < height) cell(r, c)]));
      } else {
        final k = edge - hCount;
        final r = k ~/ (width + 1), c = k % (width + 1);
        edgeDots.add(List.unmodifiable([dot(r, c), dot(r + 1, c)]));
        edgeCells.add(List.unmodifiable([if (c > 0) cell(r, c - 1), if (c < width) cell(r, c)]));
      }
    }
  }

  static const int minSize = 2;
  static const int maxSize = 12;

  final int width;
  final int height;
  final int hCount;
  final int vCount;

  int get cellCount => width * height;
  int get dotCount => (height + 1) * (width + 1);
  int get edgeCount => hCount + vCount;

  /// The four edges around each cell: top, bottom, left, right.
  final List<List<int>> cellEdges = [];

  /// The two to four edges meeting at each dot.
  final List<List<int>> dotEdges = [];

  /// The two dots an edge joins.
  final List<List<int>> edgeDots = [];

  /// The one or two cells an edge borders.
  final List<List<int>> edgeCells = [];

  int cell(int r, int c) => r * width + c;
  int dot(int r, int c) => r * (width + 1) + c;
  int h(int r, int c) => r * width + c;
  int v(int r, int c) => hCount + r * (width + 1) + c;

  bool isHorizontal(int edge) => edge < hCount;

  /// Row of a horizontal edge (`0..height`) or of a vertical edge (`0..height - 1`).
  int edgeRow(int edge) => edge < hCount ? edge ~/ width : (edge - hCount) ~/ (width + 1);

  /// Column of a horizontal edge (`0..width - 1`) or of a vertical edge (`0..width`).
  int edgeCol(int edge) => edge < hCount ? edge % width : (edge - hCount) % (width + 1);

  int cellRow(int cell) => cell ~/ width;
  int cellCol(int cell) => cell % width;

  bool sameSize(LoopGrid other) => other.width == width && other.height == height;
}
