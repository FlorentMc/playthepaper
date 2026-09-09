/// A valid Before & After puzzle: payload order [b, d, a, c], correct order
/// [a, b, c, d], so no event starts in its place.
Map<String, dynamic> flightPayload() => {
      'title': 'Milestones of flight',
      'events': <Object?>[
        {'id': 'b', 'text': 'Charles Lindbergh flies solo across the Atlantic'},
        {'id': 'd', 'text': 'Concorde makes its first flight'},
        {'id': 'a', 'text': 'The Wright brothers make the first powered flight'},
        {'id': 'c', 'text': 'The first jet aircraft takes off'},
      ],
    };

Map<String, dynamic> flightReveal() => {
      'order': ['a', 'b', 'c', 'd'],
      'dates': <String, Object?>{'a': '1903', 'b': '1927', 'c': '1939', 'd': '1969'},
      'explanation': 'Powered flight began on a beach in North Carolina. Within a lifetime passengers were crossing the Atlantic faster than sound.',
    };

Map<String, dynamic> flightItem() => {
      'topic': 'Milestones of flight',
      'payload': flightPayload(),
      'reveal': flightReveal(),
      'sources': [
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Wright_Flyer', 'excerpt': 'It made its first flight on 17 December 1903.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Charles_Lindbergh', 'excerpt': 'On 20–21 May 1927 he made the flight.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Heinkel_He_178', 'excerpt': 'It first flew on 27 August 1939.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Concorde', 'excerpt': 'It first flew in 1969.'},
      ],
      'editorNotes': 'Fixture.',
    };
