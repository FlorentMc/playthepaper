import 'package:equatable/equatable.dart';

/// One event card: a short id used by the reveal and the text shown to the
/// player. The text never carries a year.
class ChronologyEvent extends Equatable {
  const ChronologyEvent({required this.id, required this.text});

  final String id;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'text': text};

  @override
  List<Object?> get props => [id, text];
}

/// Before & After: four dated events from one theme, shown in a shuffled
/// order; the player puts them earliest first.
///
/// Payload: `{"title": "Milestones of flight", "events": [{"id": "a", "text": "..."}, ×4]}`
/// in the shuffled order the player sees. Reveal: `{"order": ["c", "a", "d", "b"],
/// "dates": {"a": "1969", ...}, "explanation": "two plain sentences"}`.
///
/// [parse] rejects: any shape error; repeated ids or texts; an order that is
/// not a permutation of the ids; a date that is not a year (`1969`, `79`,
/// `44 BC`); two events in the same year; an order that is not earliest
/// first; an event text that contains any of the years; and a payload
/// order that leaves any event in its correct place, which would make the
/// puzzle partly solved before play.
class ChronologyPuzzle extends Equatable {
  const ChronologyPuzzle._({
    required this.title,
    required this.events,
    required this.order,
    required this.dates,
    required this.years,
    required this.explanation,
  });

  static const int eventCount = 4;

  static final RegExp _datePattern = RegExp(r'^(\d{1,4})( BCE?)?$');

  /// The theme, when the content names one.
  final String? title;

  /// The events in the shuffled order shown at the start of play.
  final List<ChronologyEvent> events;

  /// Event ids, earliest first.
  final List<String> order;

  /// Event id to its date label, as written in the content.
  final Map<String, String> dates;

  /// Event id to its year; BC years are negative.
  final Map<String, int> years;

  /// Two plain sentences shown after submitting.
  final String explanation;

  List<String> get eventIds => events.map((e) => e.id).toList(growable: false);

  ChronologyEvent eventById(String id) => events.firstWhere((e) => e.id == id);

  /// Where [id] belongs, 0 for the earliest.
  int positionOf(String id) => order.indexOf(id);

  /// The year written in [date], negative for BC. Throws [FormatException]
  /// on anything that is not a year.
  static int yearOf(String date) {
    final m = _datePattern.firstMatch(date.trim());
    if (m == null) throw FormatException('Chronology date must be a year such as "1969" or "44 BC", not "$date"');
    final year = int.parse(m.group(1)!);
    if (year == 0) throw const FormatException('Chronology date cannot be year 0');
    return m.group(2) == null ? year : -year;
  }

  static ChronologyPuzzle parse(Map<String, dynamic> payload, Map<String, dynamic> reveal) {
    final rawTitle = payload['title'];
    if (rawTitle != null && (rawTitle is! String || rawTitle.trim().isEmpty)) {
      throw const FormatException('Chronology "title" must be a non-empty string when present');
    }
    final rawEvents = payload['events'];
    if (rawEvents is! List || rawEvents.length != eventCount) {
      throw const FormatException('Chronology payload needs exactly $eventCount "events"');
    }
    final events = <ChronologyEvent>[];
    final seenTexts = <String>{};
    for (var i = 0; i < rawEvents.length; i++) {
      final raw = rawEvents[i];
      if (raw is! Map) throw FormatException('Chronology event ${i + 1} must be an object');
      final id = raw['id'];
      final text = raw['text'];
      if (id is! String || id.trim().isEmpty) throw FormatException('Chronology event ${i + 1} needs an "id"');
      if (text is! String || text.trim().isEmpty) throw FormatException('Chronology event ${i + 1} needs a "text"');
      if (events.any((e) => e.id == id)) throw FormatException('Chronology event id "$id" is repeated');
      if (!seenTexts.add(text.trim().toLowerCase())) throw FormatException('Chronology event text is repeated: "$text"');
      events.add(ChronologyEvent(id: id, text: text));
    }
    final ids = events.map((e) => e.id).toSet();

    final rawOrder = reveal['order'];
    if (rawOrder is! List || rawOrder.length != eventCount || rawOrder.any((o) => o is! String)) {
      throw const FormatException('Chronology reveal needs an "order" of $eventCount event ids');
    }
    final order = rawOrder.cast<String>();
    if (order.toSet().length != eventCount || !ids.containsAll(order)) {
      throw const FormatException('Chronology "order" must list every event id exactly once');
    }

    final rawDates = reveal['dates'];
    if (rawDates is! Map) throw const FormatException('Chronology reveal needs "dates"');
    final dates = <String, String>{};
    final years = <String, int>{};
    for (final id in order) {
      final date = rawDates[id];
      if (date is! String) throw FormatException('Chronology "dates" is missing event "$id"');
      dates[id] = date.trim();
      years[id] = yearOf(date);
    }
    if (rawDates.length != eventCount) {
      throw const FormatException('Chronology "dates" must hold exactly one date per event');
    }
    if (years.values.toSet().length != eventCount) {
      throw const FormatException('Chronology events must all be in different years');
    }
    for (var i = 1; i < order.length; i++) {
      if (years[order[i]]! <= years[order[i - 1]]!) {
        throw FormatException('Chronology "order" is not earliest first: "${order[i - 1]}" is not before "${order[i]}"');
      }
    }
    for (final event in events) {
      for (final year in years.values) {
        if (RegExp('(?<!\\d)${year.abs()}(?!\\d)').hasMatch(event.text)) {
          throw FormatException('Chronology event "${event.id}" gives away the year ${year.abs()}');
        }
      }
    }
    for (var i = 0; i < events.length; i++) {
      if (events[i].id == order[i]) {
        throw FormatException('Chronology event "${events[i].id}" is already in its correct place; shuffle the payload');
      }
    }

    final explanation = reveal['explanation'];
    if (explanation is! String || explanation.trim().isEmpty) {
      throw const FormatException('Chronology reveal needs an "explanation"');
    }

    return ChronologyPuzzle._(
      title: rawTitle as String?,
      events: List.unmodifiable(events),
      order: List.unmodifiable(order),
      dates: Map.unmodifiable(dates),
      years: Map.unmodifiable(years),
      explanation: explanation,
    );
  }

  Map<String, dynamic> toPayload() => {
        if (title != null) 'title': title,
        'events': events.map((e) => e.toJson()).toList(),
      };

  Map<String, dynamic> toReveal() => {
        'order': order,
        'dates': {for (final id in order) id: dates[id]},
        'explanation': explanation,
      };

  @override
  List<Object?> get props => [title, events, order, dates, explanation];
}
