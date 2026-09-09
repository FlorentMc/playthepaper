/// A valid Five Clues puzzle: five clues to HONEY, hardest first.
Map<String, dynamic> honeyPayload() => {
      'clues': <Object?>[
        'High sugar and low pH keep microbes out, so a sealed jar does not spoil',
        'Cave paintings in Spain show people gathering it eight thousand years ago',
        'Mostly fructose and glucose, about as sweet as table sugar',
        'Stored in a wax structure of thousands of six-sided cells',
        'Bees gather nectar and refine it into this thick, sweet food',
      ],
    };

Map<String, dynamic> honeyReveal() => {
      'answer': 'Honey',
      'aliases': ['runny honey'],
      'explanations': <Object?>[
        'Its high sugar concentration and acidic pH stop microorganisms growing, so a stored jar does not spoil.',
        'Cave paintings at Cuevas de la Araña in Spain show people foraging for it 8,000 years ago.',
        'It is sweet because of its high concentrations of fructose and glucose, about as sweet as table sugar.',
        'Bees store it in honeycomb, a beeswax structure of hundreds or thousands of hexagonal cells.',
        'Bees gather floral nectar and refine it until it thickens into honey.',
      ],
    };

Map<String, dynamic> honeyItem() => {
      'topic': 'Honey',
      'payload': honeyPayload(),
      'reveal': honeyReveal(),
      'sources': [
        {
          'publisher': 'Wikipedia',
          'url': 'https://en.wikipedia.org/wiki/Honey',
          'excerpt': 'Honey is a sweet and viscous substance made by several species of bees.',
        },
      ],
      'editorNotes': 'Fixture.',
    };
