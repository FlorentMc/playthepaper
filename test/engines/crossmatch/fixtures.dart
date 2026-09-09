/// A valid Crossmatch puzzle. Rows are kinds of place, columns are countries,
/// and Surtsey is both an island and a volcano in Iceland, so it fits two
/// cells; Hekla fits only one of them, which is what makes the grid unique.
Map<String, dynamic> placesPayload() => {
      'title': 'Islands and volcanoes',
      'rows': ['City', 'Island', 'Volcano'],
      'cols': ['In Italy', 'In Iceland', 'In Japan'],
      'tiles': ['Hekla', 'Osaka', 'Vesuvius', 'Surtsey', 'Naples', 'Sakurajima', 'Okinawa', 'Sicily', 'Reykjavik'],
    };

Map<String, dynamic> placesReveal() => {
      'grid': [
        ['Naples', 'Reykjavik', 'Osaka'],
        ['Sicily', 'Surtsey', 'Okinawa'],
        ['Vesuvius', 'Hekla', 'Sakurajima'],
      ],
      'explanations': <String, Object?>{
        'Naples': 'The largest city of southern Italy, on the bay of the same name.',
        'Reykjavik': 'The capital and largest city of Iceland.',
        'Osaka': 'A port city in the Kansai region of Japan.',
        'Sicily': 'The largest island in the Mediterranean and a region of Italy.',
        'Surtsey': 'A young volcanic island off the south coast of Iceland.',
        'Okinawa': 'The largest island of the Okinawa group, in southern Japan.',
        'Vesuvius': 'The volcano above the bay of Naples in Italy.',
        'Hekla': 'One of the most active volcanoes in Iceland.',
        'Sakurajima': 'An active volcano in southern Japan.',
      },
      'fits': <String, Object?>{
        'Naples': [
          [0, 0],
        ],
        'Reykjavik': [
          [0, 1],
        ],
        'Osaka': [
          [0, 2],
        ],
        'Sicily': [
          [1, 0],
        ],
        'Surtsey': [
          [1, 1],
          [2, 1],
        ],
        'Okinawa': [
          [1, 2],
        ],
        'Vesuvius': [
          [2, 0],
        ],
        'Hekla': [
          [2, 1],
        ],
        'Sakurajima': [
          [2, 2],
        ],
      },
    };

Map<String, dynamic> placesItem() => {
      'topic': 'Islands and volcanoes',
      'payload': placesPayload(),
      'reveal': placesReveal(),
      'sources': [
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Naples', 'excerpt': 'Naples is the regional capital of Campania in Italy.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Reykjavik', 'excerpt': 'Reykjavik is the capital and largest city of Iceland.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Osaka', 'excerpt': 'Osaka is a designated city in the Kansai region of Japan.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Sicily', 'excerpt': 'Sicily is the largest island in the Mediterranean Sea and a region of Italy.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Surtsey', 'excerpt': 'Surtsey is a volcanic island off the southern coast of Iceland.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Okinawa_Island', 'excerpt': 'Okinawa Island is the largest of the Okinawa Islands of Japan.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Mount_Vesuvius', 'excerpt': 'Mount Vesuvius is a somma-stratovolcano on the Gulf of Naples in Italy.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Hekla', 'excerpt': 'Hekla is an active stratovolcano in the south of Iceland.'},
        {'publisher': 'Wikipedia', 'url': 'https://en.wikipedia.org/wiki/Sakurajima', 'excerpt': 'Sakurajima is an active stratovolcano in Kagoshima Prefecture, Japan.'},
      ],
      'editorNotes': 'Fixture.',
    };
