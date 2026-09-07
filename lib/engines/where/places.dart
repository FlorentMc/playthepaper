import 'package:equatable/equatable.dart';

/// A named place from the Natural Earth populated-places set, offered as a
/// keyboard-friendly way to put a pin on the map.
class Place extends Equatable {
  const Place({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
    required this.population,
  });

  final String name;
  final String country;
  final double lat;
  final double lon;
  final int population;

  String get label => '$name, $country';

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || country.toLowerCase().contains(q);
  }

  @override
  List<Object?> get props => [name, country, lat, lon, population];
}

/// Parses a GeoJSON FeatureCollection whose features carry `name`,
/// `adm0name`, `latitude`, `longitude` and `pop_max` properties. Features
/// missing any of these are skipped. The result is sorted by population,
/// largest first.
List<Place> parsePlaces(Map<String, dynamic> geojson) {
  final features = geojson['features'];
  if (features is! List) throw const FormatException('places: not a FeatureCollection');
  final places = <Place>[];
  for (final f in features) {
    if (f is! Map) continue;
    final props = f['properties'];
    if (props is! Map) continue;
    final name = props['name'];
    final country = props['adm0name'];
    final lat = props['latitude'];
    final lon = props['longitude'];
    final pop = props['pop_max'];
    if (name is! String || name.isEmpty || country is! String || country.isEmpty) continue;
    if (lat is! num || lon is! num) continue;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
    places.add(Place(
      name: name,
      country: country,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      population: pop is num ? pop.toInt() : 0,
    ));
  }
  places.sort((a, b) {
    final byPop = b.population.compareTo(a.population);
    return byPop != 0 ? byPop : a.name.compareTo(b.name);
  });
  return places;
}
