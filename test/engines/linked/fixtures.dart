/// A valid Linked Clues puzzle: green, white and orange lead to the flag of
/// Ireland.
Map<String, dynamic> flagPayload() => {
      'sets': <Object?>[
        {
          'clues': <Object?>[
            'The colour between cyan and yellow on the visible spectrum',
            'Chlorophyll is the largest source of it in nature',
          ],
          'hint': 'The benches of the House of Commons are this colour',
        },
        {
          'clues': <Object?>[
            'The lightest colour there is, and the one with no chroma',
            'It reflects and scatters every visible wavelength of light',
          ],
          'hint': 'The colour of snow, of chalk and of milk',
        },
        {
          'clues': <Object?>[
            'It lies between yellow and red, and is named after a fruit',
            'Carotenes give it to carrots, pumpkins and sweet potatoes',
          ],
          'hint': 'It has long been the national colour of the Netherlands',
        },
      ],
      'finalHint': 'A vertical banner of three bands, half as high as it is wide',
    };

Map<String, dynamic> flagReveal() => {
      'answers': <Object?>['Green', 'White', 'Orange'],
      'aliases': <Object?>[
        <Object?>[],
        <Object?>[],
        <Object?>['orange colour'],
      ],
      'final': 'The flag of Ireland',
      'finalAliases': <Object?>['Irish flag'],
      'explanations': <Object?>[
        'Green lies between cyan and yellow on the spectrum, and chlorophyll is its largest source in nature.',
        'White is the lightest colour and has no chroma, because it reflects and scatters every visible wavelength.',
        'Orange sits between yellow and red on the spectrum and is named after the fruit.',
        'The national flag of Ireland is a vertical tricolour of green at the hoist, then white, then orange.',
      ],
    };

Map<String, dynamic> flagItem() => {
      'topic': 'The flag of Ireland',
      'payload': flagPayload(),
      'reveal': flagReveal(),
      'sources': [
        {
          'publisher': 'Wikipedia',
          'url': 'https://en.wikipedia.org/wiki/Flag_of_Ireland',
          'excerpt': 'The national flag of Ireland is a vertical tricolour of green (at the hoist), white and orange.',
        },
      ],
      'editorNotes': 'Fixture.',
    };
