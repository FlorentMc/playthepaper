import 'package:playthepaper/engines/uncover/uncover.dart';

/// A valid Uncover puzzle. The subject is two words, one alias is a phrase,
/// and "paper" appears once on its own so tests can prove that a subject word
/// stays shut even when it is guessed.
const String boatText =
    'A paper boat is a toy folded from one flat sheet, and almost every child makes one sooner or later. '
    'The folder creases the sheet in half, turns the corners down, opens the middle and pulls the sides '
    'apart until a small hull with a raised prow appears. Set on a puddle it floats for a few minutes, '
    'then the fibres drink the water and the paper boat sinks quietly. Sailors once folded paper ships '
    'for luck before a voyage. Thick paper holds its shape for longer, and no glue, no tape and no '
    'scissors are needed, only clean folds along each edge.';

const String boatMaskedText =
    'A ▇▇▇ ▇▇▇ is a toy folded from one flat sheet, and almost every child makes one sooner or later. '
    'The folder creases the sheet in half, turns the corners down, opens the middle and pulls the sides '
    'apart until a small hull with a raised prow appears. Set on a puddle it floats for a few minutes, '
    'then the fibres drink the water and the ▇▇▇ ▇▇▇ sinks quietly. Sailors once folded ▇▇▇ ▇▇▇ '
    'for luck before a voyage. Thick ▇▇▇ holds its shape for longer, and no glue, no tape and no '
    'scissors are needed, only clean folds along each edge.';

Map<String, dynamic> boatPayload() => {
      'text': boatMaskedText,
      'hints': <String>['A toy.', 'It begins with P.', 'It is folded, never built.'],
    };

Map<String, dynamic> boatReveal() => {
      'text': boatText,
      'subject': 'Paper Boat',
      'aliases': <String>['paper ship'],
      'answerWords': <String>['paper', 'boat'],
    };

Map<String, dynamic> boatItem() => {
      'topic': 'A toy from one sheet',
      'payload': boatPayload(),
      'reveal': boatReveal(),
      'sources': [
        {
          'publisher': 'Wikipedia',
          'url': 'https://en.wikipedia.org/wiki/Paper_boat',
          'excerpt': 'A paper boat is a toy boat made out of paper.',
        },
      ],
      'editorNotes': 'Fixture.',
    };

UncoverPuzzle boatPuzzle() => UncoverPuzzle.parse(boatPayload(), boatReveal());
