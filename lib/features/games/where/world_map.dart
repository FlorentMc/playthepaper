import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../../core/theme.dart';

class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;
}

/// Natural Earth land polygons as rings of (lon, lat) points, loaded once.
class LandShapes {
  const LandShapes(this.rings);

  final List<List<Offset>> rings;

  static Future<LandShapes>? _future;

  static Future<LandShapes> load({AssetBundle? bundle}) =>
      _future ??= (bundle ?? rootBundle).loadString('assets/map/ne_110m_land.geojson').then(
            (raw) => parse(jsonDecode(raw) as Map<String, dynamic>),
          );

  static LandShapes parse(Map<String, dynamic> geojson) {
    final rings = <List<Offset>>[];
    void addRing(List ring) {
      final pts = <Offset>[];
      for (final p in ring) {
        if (p is List && p.length >= 2) pts.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
      if (pts.length >= 3) rings.add(pts);
    }

    final features = geojson['features'];
    if (features is! List) return const LandShapes([]);
    for (final f in features) {
      final geometry = f is Map ? f['geometry'] : null;
      if (geometry is! Map) continue;
      final coords = geometry['coordinates'];
      switch (geometry['type']) {
        case 'Polygon':
          for (final ring in coords as List) {
            addRing(ring as List);
          }
        case 'MultiPolygon':
          for (final polygon in coords as List) {
            for (final ring in polygon as List) {
              addRing(ring as List);
            }
          }
      }
    }
    return LandShapes(rings);
  }
}

/// Equirectangular projection onto a canvas of [size] (2:1).
Offset projectLatLon(double lat, double lon, Size size) =>
    Offset((lon + 180) / 360 * size.width, (90 - lat) / 180 * size.height);

LatLon unprojectPoint(Offset p, Size size) => LatLon(
      (90 - p.dy / size.height * 180).clamp(-90.0, 90.0),
      (p.dx / size.width * 360 - 180).clamp(-180.0, 180.0),
    );

/// A pannable, zoomable world map. A tap places the pin; the target and the
/// line between them appear once [target] is set.
class WorldMap extends StatefulWidget {
  const WorldMap({super.key, this.pin, this.target, this.onTap, this.distanceLabel, this.bundle});

  final LatLon? pin;
  final LatLon? target;
  final void Function(double lat, double lon)? onTap;
  final String? distanceLabel;
  final AssetBundle? bundle;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  final TransformationController _transform = TransformationController();
  final _LandPathCache _paths = _LandPathCache();
  LandShapes? _land;
  bool _loadFailed = false;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    LandShapes.load(bundle: widget.bundle).then((land) {
      if (mounted) setState(() => _land = land);
    }, onError: (Object _) {
      if (mounted) setState(() => _loadFailed = true);
    });
  }

  void _onTransform() {
    final s = _transform.value.getMaxScaleOnAxis();
    if ((s - _scale).abs() > 0.01) setState(() => _scale = s);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final pinText = widget.pin == null ? 'No pin placed.' : 'Pin placed.';
    final targetText = widget.target == null ? '' : ' Target shown.';
    final hint = widget.onTap == null ? '' : ' Tap to place a pin, or use Choose from a list.';
    return Semantics(
      label: 'World map. $pinText$targetText$hint',
      child: AspectRatio(
        aspectRatio: 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: colors.cellBorder)),
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 8,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: widget.onTap == null
                        ? null
                        : (d) {
                            final ll = unprojectPoint(d.localPosition, size);
                            widget.onTap!(ll.lat, ll.lon);
                          },
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: _MapPainter(
                          land: _land,
                          paths: _paths,
                          loadFailed: _loadFailed,
                          pin: widget.pin,
                          target: widget.target,
                          scale: _scale,
                          colors: colors,
                          ink: theme.colorScheme.onSurface,
                          accent: theme.colorScheme.secondary,
                          label: widget.distanceLabel,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LandPathCache {
  Size? _size;
  LandShapes? _land;
  Path? _path;

  Path pathFor(LandShapes land, Size size) {
    if (_path != null && _size == size && identical(_land, land)) return _path!;
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in land.rings) {
      for (var i = 0; i < ring.length; i++) {
        final p = projectLatLon(ring[i].dy, ring[i].dx, size);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
    }
    _size = size;
    _land = land;
    _path = path;
    return path;
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.land,
    required this.paths,
    required this.loadFailed,
    required this.pin,
    required this.target,
    required this.scale,
    required this.colors,
    required this.ink,
    required this.accent,
    required this.label,
  });

  final LandShapes? land;
  final _LandPathCache paths;
  final bool loadFailed;
  final LatLon? pin;
  final LatLon? target;
  final double scale;
  final GameColors colors;
  final Color ink;
  final Color accent;
  final String? label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.cell);

    final grat = Paint()
      ..color = colors.rule
      ..strokeWidth = 0.6 / scale
      ..style = PaintingStyle.stroke;
    for (var lon = -150; lon <= 150; lon += 30) {
      final x = projectLatLon(0, lon.toDouble(), size).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grat);
    }
    for (var lat = -60; lat <= 60; lat += 30) {
      final y = projectLatLon(lat.toDouble(), 0, size).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grat);
    }

    if (land != null) {
      final path = paths.pathFor(land!, size);
      canvas.drawPath(path, Paint()..color = colors.cellHighlight);
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.cellBorder
          ..strokeWidth = 0.7 / scale
          ..style = PaintingStyle.stroke,
      );
    } else if (loadFailed) {
      final tp = TextPainter(
        text: TextSpan(text: 'Map unavailable', style: TextStyle(color: colors.subtle, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
    }

    final pinPoint = pin == null ? null : projectLatLon(pin!.lat, pin!.lon, size);
    final targetPoint = target == null ? null : projectLatLon(target!.lat, target!.lon, size);

    if (pinPoint != null && targetPoint != null) {
      final line = Paint()
        ..color = ink
        ..strokeWidth = 1.5 / scale
        ..style = PaintingStyle.stroke;
      final dx = targetPoint.dx - pinPoint.dx;
      if (dx.abs() > size.width / 2) {
        final wrapRight = dx < 0;
        final edgeA = Offset(wrapRight ? size.width : 0, (pinPoint.dy + targetPoint.dy) / 2);
        final edgeB = Offset(wrapRight ? 0 : size.width, (pinPoint.dy + targetPoint.dy) / 2);
        canvas.drawLine(pinPoint, edgeA, line);
        canvas.drawLine(edgeB, targetPoint, line);
      } else {
        canvas.drawLine(pinPoint, targetPoint, line);
      }
      if (label != null) {
        final mid = dx.abs() > size.width / 2
            ? Offset(pinPoint.dx, pinPoint.dy - 14 / scale)
            : Offset((pinPoint.dx + targetPoint.dx) / 2, (pinPoint.dy + targetPoint.dy) / 2);
        final tp = TextPainter(
          text: TextSpan(text: label, style: TextStyle(color: ink, fontSize: 11 / scale, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        final pad = 3 / scale;
        final rect = Rect.fromCenter(center: mid, width: tp.width + pad * 2, height: tp.height + pad * 2);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(3 / scale)), Paint()..color = colors.cell);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(3 / scale)),
          Paint()
            ..color = colors.cellBorder
            ..strokeWidth = 0.6 / scale
            ..style = PaintingStyle.stroke,
        );
        tp.paint(canvas, rect.topLeft + Offset(pad, pad));
      }
    }

    if (targetPoint != null) {
      final r = 7 / scale;
      final diamond = Path()
        ..moveTo(targetPoint.dx, targetPoint.dy - r)
        ..lineTo(targetPoint.dx + r, targetPoint.dy)
        ..lineTo(targetPoint.dx, targetPoint.dy + r)
        ..lineTo(targetPoint.dx - r, targetPoint.dy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = colors.correct);
      canvas.drawPath(
        diamond,
        Paint()
          ..color = colors.onFeedback
          ..strokeWidth = 1.2 / scale
          ..style = PaintingStyle.stroke,
      );
    }

    if (pinPoint != null) {
      final r = 6 / scale;
      canvas.drawCircle(pinPoint, r, Paint()..color = accent);
      canvas.drawCircle(
        pinPoint,
        r,
        Paint()
          ..color = colors.onFeedback
          ..strokeWidth = 1.2 / scale
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(pinPoint, 1.5 / scale, Paint()..color = colors.onFeedback);
      final cross = Paint()
        ..color = accent
        ..strokeWidth = 1 / scale;
      canvas.drawLine(pinPoint + Offset(0, -r - 5 / scale), pinPoint + Offset(0, -r - 1 / scale), cross);
      canvas.drawLine(pinPoint + Offset(0, r + 1 / scale), pinPoint + Offset(0, r + 5 / scale), cross);
      canvas.drawLine(pinPoint + Offset(-r - 5 / scale, 0), pinPoint + Offset(-r - 1 / scale, 0), cross);
      canvas.drawLine(pinPoint + Offset(r + 1 / scale, 0), pinPoint + Offset(r + 5 / scale, 0), cross);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.land != land ||
      old.loadFailed != loadFailed ||
      old.pin?.lat != pin?.lat ||
      old.pin?.lon != pin?.lon ||
      old.target?.lat != target?.lat ||
      old.target?.lon != target?.lon ||
      old.scale != scale ||
      old.label != label ||
      old.colors != colors ||
      old.ink != ink ||
      old.accent != accent;
}

/// Distance formatted for a map label, e.g. `1,240 km`.
String formatKm(double km) {
  final n = km.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - i - 1;
    if (left > 0 && left % 3 == 0) buf.write(',');
  }
  return '$buf km';
}

