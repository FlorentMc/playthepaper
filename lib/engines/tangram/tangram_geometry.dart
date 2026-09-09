import 'dart:math' as math;

/// Plane geometry for the seven pieces, in board units.
///
/// The board is [TangramGeometry.boardUnits] units square. The origin is the
/// top left corner and y increases downwards, as on screen, so a positive
/// signed area means the vertices run clockwise as drawn.
class TangramPoint {
  const TangramPoint(this.x, this.y);

  final double x;
  final double y;

  TangramPoint operator +(TangramPoint other) => TangramPoint(x + other.x, y + other.y);
  TangramPoint operator -(TangramPoint other) => TangramPoint(x - other.x, y - other.y);

  bool get isLattice => x == x.roundToDouble() && y == y.roundToDouble();

  @override
  bool operator ==(Object other) => other is TangramPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${_format(x)}, ${_format(y)})';

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(4);
}

/// A silhouette rasterised on a square grid of [resolution] samples per board
/// unit. `1` marks a sample inside the shape.
class TangramMask {
  const TangramMask._(this.rows, this.filled);

  final List<String> rows;

  /// How many samples fall inside the shape.
  final int filled;

  int get size => rows.length;

  bool at(int col, int row) => rows[row].codeUnitAt(col) == 0x31;

  /// Samples set in exactly one of the two masks.
  int difference(TangramMask other) {
    if (other.size != size) throw const FormatException('Tangram masks differ in size');
    var count = 0;
    for (var row = 0; row < size; row++) {
      final a = rows[row], b = other.rows[row];
      for (var col = 0; col < size; col++) {
        if (a.codeUnitAt(col) != b.codeUnitAt(col)) count++;
      }
    }
    return count;
  }

  List<String> toJson() => List<String>.of(rows);

  static TangramMask fromRows(List<String> rows) {
    if (rows.isEmpty) throw const FormatException('Tangram mask is empty');
    var filled = 0;
    for (final row in rows) {
      if (row.length != rows.length) {
        throw FormatException('Tangram mask row "$row" is not ${rows.length} wide');
      }
      for (var col = 0; col < row.length; col++) {
        final unit = row.codeUnitAt(col);
        if (unit == 0x31) {
          filled++;
        } else if (unit != 0x30) {
          throw FormatException('Tangram mask row "$row" holds something other than 0 or 1');
        }
      }
    }
    return TangramMask._(List<String>.unmodifiable(rows), filled);
  }

  static TangramMask parse(Object? raw, {required int size}) {
    if (raw is! List || raw.length != size || raw.any((r) => r is! String)) {
      throw FormatException('Tangram mask must be $size rows of $size characters');
    }
    return fromRows(raw.cast<String>());
  }
}

class TangramGeometry {
  const TangramGeometry._();

  /// The board is eight units square; the assembled square is four.
  static const int boardUnits = 8;

  /// Mask samples per board unit.
  static const int resolution = 4;

  static const int maskSize = boardUnits * resolution;

  /// The area of the seven pieces together, and so of every silhouette.
  static const double pieceArea = 16;

  static double signedArea(List<TangramPoint> polygon) {
    var sum = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i], b = polygon[(i + 1) % polygon.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum / 2;
  }

  /// Crossing test with a half-open rule on y, so a sample is inside exactly
  /// one of two polygons that share an edge. Samples on an edge are avoided
  /// by [sampleAt] rather than resolved here.
  static bool contains(List<TangramPoint> polygon, double px, double py) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i], b = polygon[j];
      if ((a.y > py) != (b.y > py) && px < a.x + (py - a.y) / (b.y - a.y) * (b.x - a.x)) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// The sample point of mask cell ([col], [row]). The offsets are chosen so
  /// that no sample ever lies on a line `x = n`, `y = n`, `x + y = n` or
  /// `x - y = n`: every piece edge runs along one of those, so no sample is
  /// ever ambiguous and the raster of a shape is exact.
  static TangramPoint sampleAt(int col, int row) => TangramPoint(
        (col + 0.5) / resolution,
        (row + 0.25) / resolution,
      );

  /// Rasterises everything covered by at least one of [polygons].
  static TangramMask rasteriseUnion(Iterable<List<TangramPoint>> polygons) =>
      _rasterise(polygons, evenOdd: false);

  /// Rasterises a set of outline loops, where a loop wound against the others
  /// is a hole and stays empty.
  static TangramMask rasteriseOutline(Iterable<List<TangramPoint>> loops) =>
      _rasterise(loops, evenOdd: true);

  static TangramMask _rasterise(Iterable<List<TangramPoint>> polygons, {required bool evenOdd}) {
    final shapes = polygons.toList(growable: false);
    final rows = <String>[];
    for (var row = 0; row < maskSize; row++) {
      final buffer = StringBuffer();
      for (var col = 0; col < maskSize; col++) {
        final p = sampleAt(col, row);
        var inside = false;
        for (final shape in shapes) {
          if (contains(shape, p.x, p.y)) {
            inside = evenOdd ? !inside : true;
            if (inside && !evenOdd) break;
          }
        }
        buffer.write(inside ? '1' : '0');
      }
      rows.add(buffer.toString());
    }
    return TangramMask.fromRows(rows);
  }

  /// The area shared by two convex polygons, both wound clockwise as drawn.
  static double overlapArea(List<TangramPoint> a, List<TangramPoint> b) {
    var clipped = a;
    for (var i = 0; i < b.length && clipped.isNotEmpty; i++) {
      clipped = _clip(clipped, b[i], b[(i + 1) % b.length]);
    }
    return clipped.length < 3 ? 0 : signedArea(clipped).abs();
  }

  /// Sutherland–Hodgman against the half plane left of `edgeA -> edgeB`.
  static List<TangramPoint> _clip(List<TangramPoint> polygon, TangramPoint edgeA, TangramPoint edgeB) {
    double side(TangramPoint p) =>
        (edgeB.x - edgeA.x) * (p.y - edgeA.y) - (edgeB.y - edgeA.y) * (p.x - edgeA.x);
    final out = <TangramPoint>[];
    for (var i = 0; i < polygon.length; i++) {
      final current = polygon[i], previous = polygon[(i + polygon.length - 1) % polygon.length];
      final sCurrent = side(current), sPrevious = side(previous);
      if (sCurrent >= 0) {
        if (sPrevious < 0) out.add(_intersect(previous, current, sPrevious, sCurrent));
        out.add(current);
      } else if (sPrevious >= 0) {
        out.add(_intersect(previous, current, sPrevious, sCurrent));
      }
    }
    return out;
  }

  static TangramPoint _intersect(TangramPoint a, TangramPoint b, double sa, double sb) {
    final t = sa / (sa - sb);
    return TangramPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  }

  /// The outline of the union of [polygons], as one loop per closed contour.
  ///
  /// Every vertex must sit on the board lattice and every edge must run along
  /// an axis or a 45° diagonal, which is true of the seven pieces at a
  /// quarter turn. Each edge is cut into unit steps; a step that appears in
  /// both directions lies between two pieces and drops out, and the steps
  /// that survive are chained into loops. The arithmetic is exact, so the
  /// outline is exact.
  static List<List<TangramPoint>> unionOutline(Iterable<List<TangramPoint>> polygons) {
    final steps = <int, Set<int>>{};
    void addStep(int from, int to) {
      final back = steps[to];
      if (back != null && back.remove(from)) {
        if (back.isEmpty) steps.remove(to);
        return;
      }
      steps.putIfAbsent(from, () => <int>{}).add(to);
    }

    for (final polygon in polygons) {
      for (var i = 0; i < polygon.length; i++) {
        final a = polygon[i], b = polygon[(i + 1) % polygon.length];
        if (!a.isLattice || !b.isLattice) {
          throw FormatException('Tangram outline needs lattice points, got $a and $b');
        }
        final dx = (b.x - a.x).round(), dy = (b.y - a.y).round();
        final length = math.max(dx.abs(), dy.abs());
        if (length == 0) continue;
        if ((dx != 0 && dx.abs() != length) || (dy != 0 && dy.abs() != length)) {
          throw FormatException('Tangram edge $a to $b is neither square nor diagonal');
        }
        final stepX = dx.sign, stepY = dy.sign;
        var x = a.x.round(), y = a.y.round();
        for (var k = 0; k < length; k++) {
          addStep(_key(x, y), _key(x + stepX, y + stepY));
          x += stepX;
          y += stepY;
        }
      }
    }

    final loops = <List<TangramPoint>>[];
    while (steps.isNotEmpty) {
      final start = steps.keys.first;
      var from = start;
      var to = steps[from]!.first;
      final walk = <int>[from];
      while (true) {
        final out = steps[from]!;
        out.remove(to);
        if (out.isEmpty) steps.remove(from);
        if (to == start) break;
        walk.add(to);
        final next = steps[to];
        if (next == null || next.isEmpty) {
          throw const FormatException('Tangram outline does not close');
        }
        final chosen = _sharpestTurn(from, to, next);
        from = to;
        to = chosen;
      }
      loops.add(_simplify(walk));
    }
    return loops;
  }

  /// Where two contours pinch at a point, the loop that keeps the inside of
  /// the shape on its right is the one that turns as far towards it as it
  /// can, so take the sharpest turn to the inside.
  static int _sharpestTurn(int from, int through, Set<int> options) {
    if (options.length == 1) return options.first;
    final inX = _x(through) - _x(from), inY = _y(through) - _y(from);
    int? best;
    var bestAngle = double.negativeInfinity;
    for (final option in options) {
      final outX = _x(option) - _x(through), outY = _y(option) - _y(through);
      final cross = (inX * outY - inY * outX).toDouble();
      final dot = (inX * outX + inY * outY).toDouble();
      final angle = math.atan2(cross, dot);
      if (angle > bestAngle) {
        bestAngle = angle;
        best = option;
      }
    }
    return best!;
  }

  static List<TangramPoint> _simplify(List<int> walk) {
    final points = <TangramPoint>[];
    for (var i = 0; i < walk.length; i++) {
      final previous = walk[(i + walk.length - 1) % walk.length];
      final current = walk[i];
      final next = walk[(i + 1) % walk.length];
      final ax = _x(current) - _x(previous), ay = _y(current) - _y(previous);
      final bx = _x(next) - _x(current), by = _y(next) - _y(current);
      if (ax * by - ay * bx != 0) {
        points.add(TangramPoint(_x(current).toDouble(), _y(current).toDouble()));
      }
    }
    return points;
  }

  static const int _origin = 32;
  static const int _span = 256;

  static int _key(int x, int y) => (x + _origin) * _span + (y + _origin);
  static int _x(int key) => key ~/ _span - _origin;
  static int _y(int key) => key % _span - _origin;
}
