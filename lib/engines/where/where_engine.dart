import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// Rules for Where: two clues, a pin on the map, and the great-circle
/// distance to the target.

Never _bad(String message) => throw FormatException('where: $message');

const double earthRadiusKm = 6371.0088;

double _radians(double degrees) => degrees * math.pi / 180;

/// Great-circle distance in kilometres between two points.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(lat1)) * math.cos(_radians(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusKm * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
}

double _lat(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is num && v.isFinite && v >= -90 && v <= 90) return v.toDouble();
  return _bad('$key must be a latitude between -90 and 90');
}

double _lon(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is num && v.isFinite && v >= -180 && v <= 180) return v.toDouble();
  return _bad('$key must be a longitude between -180 and 180');
}

/// Formats a coordinate as `48.9°N, 2.3°E`.
String formatLatLon(double lat, double lon) {
  final ns = lat < 0 ? 'S' : 'N';
  final ew = lon < 0 ? 'W' : 'E';
  return '${lat.abs().toStringAsFixed(1)}°$ns, ${lon.abs().toStringAsFixed(1)}°$ew';
}

class WherePuzzle extends Equatable {
  const WherePuzzle({required this.clues});

  final List<String> clues;

  static WherePuzzle parse(Map<String, dynamic> payload) {
    final raw = payload['clues'];
    if (raw is! List || raw.length != 2) _bad('clues must list exactly two strings');
    final clues = <String>[];
    for (final c in raw) {
      if (c is! String || c.trim().isEmpty) _bad('clues must be non-empty strings');
      clues.add(c);
    }
    return WherePuzzle(clues: clues);
  }

  Map<String, dynamic> toJson() => {'clues': clues};

  @override
  List<Object?> get props => [clues];
}

class WhereReveal extends Equatable {
  const WhereReveal({
    required this.lat,
    required this.lon,
    required this.placeName,
    required this.acceptRadiusKm,
    required this.explanation,
  });

  final double lat;
  final double lon;
  final String placeName;
  final double acceptRadiusKm;
  final String explanation;

  static WhereReveal parse(Map<String, dynamic> reveal) {
    final radius = reveal['acceptRadiusKm'];
    if (radius is! num || !radius.isFinite || radius <= 0) _bad('acceptRadiusKm must be positive');
    final name = reveal['placeName'];
    if (name is! String || name.trim().isEmpty) _bad('placeName must be a non-empty string');
    final explanation = reveal['explanation'];
    if (explanation is! String || explanation.trim().isEmpty) _bad('explanation must be a non-empty string');
    return WhereReveal(
      lat: _lat(reveal, 'lat'),
      lon: _lon(reveal, 'lon'),
      placeName: name,
      acceptRadiusKm: radius.toDouble(),
      explanation: explanation,
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'placeName': placeName,
        'acceptRadiusKm': acceptRadiusKm == acceptRadiusKm.roundToDouble() ? acceptRadiusKm.round() : acceptRadiusKm,
        'explanation': explanation,
      };

  double distanceTo(double pinLat, double pinLon) => haversineKm(pinLat, pinLon, lat, lon);

  bool solved(double distanceKm) => distanceKm <= acceptRadiusKm;

  @override
  List<Object?> get props => [lat, lon, placeName, acceptRadiusKm, explanation];
}

class WhereState extends Equatable {
  const WhereState({this.lat, this.lon, this.submitted = false});

  final double? lat;
  final double? lon;
  final bool submitted;

  bool get pinned => lat != null && lon != null;

  WhereState withPin(double lat, double lon) {
    if (submitted) return this;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) throw ArgumentError('pin outside the globe');
    return WhereState(lat: lat, lon: lon);
  }

  WhereState submit() {
    if (!pinned) throw StateError('no pin to submit');
    return WhereState(lat: lat, lon: lon, submitted: true);
  }

  Map<String, dynamic> toJson() => {
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        'submitted': submitted,
      };

  static WhereState fromJson(Map<String, dynamic> json) => WhereState(
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
        submitted: json['submitted'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [lat, lon, submitted];
}
