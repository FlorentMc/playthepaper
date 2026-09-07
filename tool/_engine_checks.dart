import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/game_kind.dart';

/// Runs a puzzle through its engine's parser. Returns null when valid,
/// otherwise a one-line description of the problem.
///
/// Engine hooks are wired in as each engine lands; an unwired game is
/// reported so the validator never silently passes it.
String? checkPuzzleWithEngine(PuzzleRecord record) {
  final check = engineChecks[record.game];
  if (check == null) return 'no engine validator for ${record.game.slug}';
  try {
    check(record);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

typedef EngineCheck = void Function(PuzzleRecord record);

final Map<GameKind, EngineCheck> engineChecks = {};

/// Answers of one news game must not appear in another's wording.
List<String> leakChecks(List<PuzzleRecord> news) {
  final errors = <String>[];
  PuzzleRecord? of(GameKind g) => news.where((r) => r.game == g).firstOrNull;
  final correct = of(GameKind.correct);
  final number = of(GameKind.number);
  final where = of(GameKind.where);

  String textOf(Map<String, dynamic> m) => m.values.map((v) => v is List || v is Map ? v.toString() : '$v').join(' ').toLowerCase();

  if (where != null) {
    final place = (where.reveal['placeName'] as String?) ?? '';
    final tokens = place
        .split(RegExp(r'[,\s]+'))
        .where((t) => t.length >= 4)
        .map((t) => t.toLowerCase())
        .toSet();
    for (final other in [correct, number].whereType<PuzzleRecord>()) {
      final text = textOf(other.payload);
      for (final t in tokens) {
        if (RegExp('\\b${RegExp.escape(t)}\\b').hasMatch(text)) {
          errors.add('${other.game.slug} wording mentions "$t", the Where answer');
        }
      }
    }
  }
  if (number != null) {
    final answer = number.reveal['answer'];
    if (answer is num) {
      final s = answer.toString();
      final plain = answer % 1 == 0 ? answer.toInt().toString() : s;
      for (final other in [correct, where].whereType<PuzzleRecord>()) {
        final text = textOf(other.payload);
        if (RegExp('\\b${RegExp.escape(plain)}\\b').hasMatch(text)) {
          errors.add('${other.game.slug} wording contains $plain, the Number answer');
        }
      }
    }
  }
  if (correct != null) {
    final options = correct.payload['options'];
    final idx = correct.reveal['correctOption'];
    if (options is List && idx is int && idx >= 0 && idx < options.length) {
      final fix = options[idx].toString().toLowerCase();
      for (final other in [number, where].whereType<PuzzleRecord>()) {
        if (textOf(other.payload).contains(fix)) {
          errors.add('${other.game.slug} wording contains "$fix", the Correct repair');
        }
      }
    }
  }
  return errors;
}
