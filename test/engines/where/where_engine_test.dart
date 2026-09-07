import 'package:daypencil/engines/where/places.dart';
import 'package:daypencil/engines/where/where_engine.dart';
import 'package:test/test.dart';

void main() {
  test('haversine London to Paris is about 344 km', () {
    final d = haversineKm(51.5074, -0.1278, 48.8566, 2.3522);
    expect(d, closeTo(344, 5));
    expect(haversineKm(10, 20, 10, 20), 0);
    expect(haversineKm(0, 0, 0, 180), closeTo(20015, 5));
  });

  test('formats coordinates', () {
    expect(formatLatLon(48.9, 2.3), '48.9°N, 2.3°E');
    expect(formatLatLon(-33.87, -70.64), '33.9°S, 70.6°W');
  });

  group('WherePuzzle and WhereReveal', () {
    test('parse valid data', () {
      final p = WherePuzzle.parse({'clues': ['A', 'B']});
      expect(p.clues, ['A', 'B']);
      final r = WhereReveal.parse({
        'lat': 48.858,
        'lon': 2.294,
        'placeName': 'Paris, France',
        'acceptRadiusKm': 300,
        'explanation': 'Because.',
      });
      expect(r.solved(300), isTrue);
      expect(r.solved(300.1), isFalse);
      expect(r.distanceTo(51.5074, -0.1278), closeTo(341, 5));
    });

    test('reject bad data', () {
      expect(() => WherePuzzle.parse({'clues': ['only one']}), throwsFormatException);
      expect(() => WherePuzzle.parse({'clues': ['a', '']}), throwsFormatException);
      final good = {'lat': 0, 'lon': 0, 'placeName': 'X', 'acceptRadiusKm': 10, 'explanation': 'y'};
      expect(() => WhereReveal.parse({...good, 'lat': 91}), throwsFormatException);
      expect(() => WhereReveal.parse({...good, 'lon': -181}), throwsFormatException);
      expect(() => WhereReveal.parse({...good, 'acceptRadiusKm': 0}), throwsFormatException);
      expect(() => WhereReveal.parse({...good, 'placeName': ''}), throwsFormatException);
    });
  });

  test('WhereState pins, submits and round-trips', () {
    const s = WhereState();
    expect(s.pinned, isFalse);
    expect(() => s.submit(), throwsStateError);
    final pinned = s.withPin(10, 20);
    expect(pinned.pinned, isTrue);
    final done = pinned.submit();
    expect(done.withPin(1, 1), done);
    expect(WhereState.fromJson(done.toJson()), done);
    expect(WhereState.fromJson(const WhereState().toJson()), const WhereState());
    expect(() => s.withPin(95, 0), throwsArgumentError);
  });

  test('parsePlaces reads a tiny GeoJSON collection', () {
    final places = parsePlaces({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'name': 'Paris', 'adm0name': 'France', 'latitude': 48.87, 'longitude': 2.33, 'pop_max': 9904000},
          'geometry': {'type': 'Point', 'coordinates': [2.33, 48.87]},
        },
        {
          'type': 'Feature',
          'properties': {'name': 'Tokyo', 'adm0name': 'Japan', 'latitude': 35.69, 'longitude': 139.75, 'pop_max': 35676000},
        },
        {
          'type': 'Feature',
          'properties': {'name': 'Nowhere', 'adm0name': 'X', 'latitude': 'bad', 'longitude': 0},
        },
      ],
    });
    expect(places.map((p) => p.name), ['Tokyo', 'Paris']);
    expect(places.last.label, 'Paris, France');
    expect(places.last.matches('fra'), isTrue);
    expect(places.last.matches('tok'), isFalse);
    expect(() => parsePlaces({'type': 'Feature'}), throwsFormatException);
  });
}
