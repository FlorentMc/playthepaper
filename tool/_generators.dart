import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:playthepaper/engines/compass/compass_generator.dart';
import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:playthepaper/engines/regions/regions.dart';

/// One daily puzzle from a seed.
typedef DailyGenerator = PuzzleRecord Function(DateTime date);

/// An editorial game: an evergreen reserve pick, or a news item from a template.
class EditorialGenerator {
  const EditorialGenerator({required this.generate, required this.fromTemplate});
  final DailyGenerator generate;
  final PuzzleRecord Function(DateTime date, Map<String, dynamic> item, {String? storyId}) fromTemplate;
}

/// Generated games (logic and play). Each module registers its generator
/// here as it lands; an unregistered game is simply absent from new editions.
final Map<GameKind, DailyGenerator> generatedGames = {
  GameKind.bridges: BridgesGenerator().generate,
  GameKind.compass: CompassGenerator().generate,
  GameKind.kakuro: KakuroGenerator().generate,
  GameKind.regions: RegionsGenerator().generate,
};

/// Editorial games with an evergreen reserve under `content_src/editorial/[slug]/`.
final Map<GameKind, EditorialGenerator> editorialGames = {};
