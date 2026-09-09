/// A valid Groups puzzle: planets, metals and stars, with Mercury the one
/// tile that could sit in two groups. No row of four is a whole group.
Map<String, dynamic> skyPayload() => {
      'tiles': <Object?>[
        'Venus', 'Mercury', 'Sirius', 'Mars',
        'Lead', 'Vega', 'Jupiter', 'Tin',
        'Rigel', 'Saturn', 'Copper', 'Altair',
      ],
    };

Map<String, dynamic> skyReveal() => {
      'groups': <Object?>[
        {
          'title': 'Planets',
          'members': ['Venus', 'Mars', 'Jupiter', 'Saturn'],
          'explanation': 'Each of these planets is bright enough to find without a telescope.',
          'alsoFits': ['Mercury'],
        },
        {
          'title': 'Metals known to the ancients',
          'members': ['Mercury', 'Lead', 'Tin', 'Copper'],
          'explanation': 'Smiths worked all four of these metals long before chemistry named them.',
        },
        {
          'title': 'Bright stars',
          'members': ['Sirius', 'Vega', 'Rigel', 'Altair'],
          'explanation': 'All four are among the brightest stars in the northern sky.',
        },
      ],
    };

Map<String, dynamic> skyItem() => {
      'topic': 'Planets, metals and stars',
      'payload': skyPayload(),
      'reveal': skyReveal(),
      'sources': [
        {
          'publisher': 'Wikipedia',
          'url': 'https://en.wikipedia.org/wiki/Solar_System',
          'excerpt': 'The planets Venus, Mars, Jupiter and Saturn are visible to the naked eye.',
        },
        {
          'publisher': 'Wikipedia',
          'url': 'https://en.wikipedia.org/wiki/Metals_of_antiquity',
          'excerpt': 'The metals of antiquity are gold, copper, silver, lead, tin, iron and mercury.',
        },
        {
          'publisher': 'Wikipedia',
          'url': 'https://en.wikipedia.org/wiki/List_of_brightest_stars',
          'excerpt': 'Sirius, Vega, Rigel and Altair are all first-magnitude stars.',
        },
      ],
      'editorNotes': 'Fixture.',
    };

/// The reveal with the payload's own tiles put back in group order, which a
/// parse must reject because the first row gives a group away.
Map<String, dynamic> orderedPayload() => {
      'tiles': <Object?>[
        'Venus', 'Mars', 'Jupiter', 'Saturn',
        'Mercury', 'Lead', 'Tin', 'Copper',
        'Sirius', 'Vega', 'Rigel', 'Altair',
      ],
    };
