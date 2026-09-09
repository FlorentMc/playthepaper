import 'dart:convert';
import 'dart:io';

import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/game_kind.dart';
import '../../core/puzzle_id.dart';
import 'compass_engine.dart';

/// Wraps a prepared Word Compass rank file in the puzzle record envelope.
///
/// The ranks are computed ahead of time by `tool/compass_prepare.py` from
/// GloVe word vectors and written to `content_src/compass/ranks/<date>.json`;
/// this class only reads and validates them. It uses `dart:io` and is meant
/// for the content tools and tests, never the app.
class CompassGenerator {
  CompassGenerator({this.ranksDir = defaultRanksDir});

  static const String defaultRanksDir = 'content_src/compass/ranks';

  /// The vector set the ranks come from, recorded as the dictionary version.
  static const String dictionaryVersion = 'glove-wiki-gigaword-300';

  /// A shipped record above this size drops the similarity values and keeps
  /// only the ranks, which are all the game needs.
  static const int maxRecordBytes = 120 * 1024;

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  final String ranksDir;

  /// The puzzle record for [date]. Throws [StateError] when no rank file has
  /// been prepared for it and [FormatException] when the file is malformed.
  PuzzleRecord generate(DateTime date) {
    final day = EditionClock.formatDate(date);
    final file = File('$ranksDir/$day.json');
    if (!file.existsSync()) {
      throw StateError(
        'No Word Compass ranks for $day: expected ${file.path}. '
        'Run: python3 tool/compass_prepare.py --vectors <glove-wiki-gigaword-300.gz> --from $day --to $day',
      );
    }
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, dynamic>) throw FormatException('${file.path} is not a JSON object');
    final target = json['target'];
    final size = json['vocabularySize'];
    final ranks = json['ranks'];
    final puzzle = CompassPuzzle.parse({'vocabularySize': size}, {'target': target, 'ranks': ranks});

    final attribution = json['licence'];
    final similarity = json['similarity'];
    final id = PuzzleId(game: GameKind.compass, date: date);
    PuzzleRecord build({required bool withSimilarity}) => PuzzleRecord(
      id: id,
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      dictionaryVersion: dictionaryVersion,
      payload: {...puzzle.toPayload(), if (attribution is String) 'attribution': attribution},
      reveal: {
        ...puzzle.toReveal(),
        if (withSimilarity && similarity is List && similarity.length == puzzle.vocabularySize)
          'similarity': similarity,
      },
    );

    var record = build(withSimilarity: true);
    if (utf8.encode(_pretty.convert(record.toJson())).length > maxRecordBytes) {
      record = build(withSimilarity: false);
    }
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>);
    if (CompassPuzzle.parse(check.payload, check.reveal) != puzzle) {
      throw StateError('Round trip failed for ${record.id}');
    }
    return record;
  }
}
