import 'package:playthepaper/content/models.dart';
import 'package:playthepaper/core/game_kind.dart';
import 'package:playthepaper/engines/binary/binary.dart';
import 'package:playthepaper/engines/bridges/bridges.dart';
import 'package:playthepaper/engines/compass/compass_engine.dart';
import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:playthepaper/engines/kakuro/kakuro.dart';
import 'package:playthepaper/engines/letters/letters.dart';
import 'package:playthepaper/engines/nonogram/nonogram.dart';
import 'package:playthepaper/engines/quiz/quiz_engine.dart';
import 'package:playthepaper/engines/regions/regions.dart';
import 'package:playthepaper/engines/target/target.dart';
import 'package:playthepaper/engines/sudoku/sudoku.dart';
import 'package:playthepaper/engines/word/word_engine.dart';

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

final Map<GameKind, EngineCheck> engineChecks = {
  GameKind.word: (r) => WordPuzzle.parse(r.payload, r.reveal),
  GameKind.sudoku: (r) => SudokuPuzzle.parse(r.payload, r.reveal),
  GameKind.letters: (r) => LettersPuzzle.parse(r.payload, r.reveal),
  GameKind.crossword: (r) => CrosswordPuzzle.parse(r.payload, r.reveal),
  GameKind.quiz: (r) => QuizPuzzle.parse(r.payload, r.reveal),
  GameKind.compass: (r) => CompassPuzzle.parse(r.payload, r.reveal),
  GameKind.bridges: (r) => BridgesPuzzle.parse(r.payload, r.reveal),
  GameKind.kakuro: (r) => KakuroPuzzle.parse(r.payload, r.reveal),
  GameKind.nonogram: (r) => NonogramPuzzle.parse(r.payload, r.reveal),
  GameKind.regions: (r) => RegionsPuzzle.parse(r.payload, r.reveal),
  GameKind.binary: (r) => BinaryPuzzle.parse(r.payload, r.reveal),
  GameKind.target: (r) => TargetPuzzle.parse(r.payload, r.reveal),
};


bool _wholeWord(String text, String word) =>
    RegExp('(?<![A-Za-z])${RegExp.escape(word)}(?![A-Za-z])', caseSensitive: false).hasMatch(text);

/// Seeding rules for one edition: teasers and excerpts present and honest,
/// quiz figures backed by sources, no seeded word doubling as a quiz option,
/// and the manifest's seeds map matching the puzzles.
List<String> seedChecks(EditionManifest m, PuzzleRecord? Function(GameKind) recordOf) {
  final errors = <String>[];
  final expectedSeeds = <String, List<String>>{};
  void feed(String storyId, String what) => expectedSeeds.putIfAbsent(storyId, () => []).add(what);
  final seededWords = <String>{};

  final word = recordOf(GameKind.word);
  if (word != null && word.storyId != null) {
    final answer = word.reveal['answer'];
    final excerpt = word.reveal['excerpt'];
    if (word.payload['teaser'] is! String || (word.payload['teaser'] as String).trim().isEmpty) {
      errors.add('word ${word.id} is seeded but has no teaser');
    }
    if (excerpt is! String || answer is! String || !_wholeWord(excerpt, answer)) {
      errors.add('word ${word.id}: the answer does not appear in its excerpt');
    }
    if (answer is String) seededWords.add(answer.toUpperCase());
    feed(word.storyId!, 'word');
  }

  final letters = recordOf(GameKind.letters);
  if (letters != null && letters.storyId != null) {
    final excerpt = letters.reveal['excerpt'];
    final pangrams = (letters.reveal['pangrams'] as List?)?.cast<String>() ?? const [];
    if (letters.payload['teaser'] is! String || (letters.payload['teaser'] as String).trim().isEmpty) {
      errors.add('letters ${letters.id} is seeded but has no teaser');
    }
    final hit = excerpt is String ? pangrams.where((p) => _wholeWord(excerpt, p)).toList() : const <String>[];
    if (hit.isEmpty) {
      errors.add('letters ${letters.id}: no pangram appears in its excerpt');
    } else {
      seededWords.addAll(hit.map((p) => p.toUpperCase()));
    }
    feed(letters.storyId!, 'letters');
  }

  final crossword = recordOf(GameKind.crossword);
  if (crossword != null) {
    final puzzle = CrosswordPuzzle.parse(crossword.payload, crossword.reveal);
    for (final s in puzzle.seeded) {
      final entry = puzzle.entries.where((e) => e.label == s.label).firstOrNull;
      if (entry == null) {
        errors.add('crossword ${crossword.id}: seeded label ${s.label} is not an entry');
        continue;
      }
      final answer = puzzle.answerOf(entry);
      if (!_wholeWord(s.excerpt, answer)) errors.add('crossword ${crossword.id}: $answer (${s.label}) not in its excerpt');
      if (entry.storyId != s.storyId) errors.add('crossword ${crossword.id}: ${s.label} story mismatch between clue and reveal');
      seededWords.add(answer.toUpperCase());
      feed(s.storyId, 'crossword:${s.label}');
    }
    if (puzzle.seeded.isNotEmpty && (puzzle.teaser == null || puzzle.teaser!.trim().isEmpty)) {
      errors.add('crossword ${crossword.id} is seeded but has no teaser');
    }
  }

  for (final g in GameKind.inCategory(GameCategory.editorial)) {
    final r = recordOf(g);
    if (r?.storyId != null) feed(r!.storyId!, g.slug);
  }

  final quiz = recordOf(GameKind.quiz);
  if (quiz != null) {
    final q = QuizPuzzle.parse(quiz.payload, quiz.reveal);
    final sourceText = quiz.sources.map((s) => s.excerpt).join('\n');
    final numberPattern = RegExp(r'\d[\d,.]*');
    for (var i = 0; i < q.questions.length; i++) {
      final question = q.questions[i];
      if (m.story(question.storyId) == null) {
        errors.add('quiz ${quiz.id}: question ${i + 1} references unknown story ${question.storyId}');
      }
      feed(question.storyId, 'quiz:${i + 1}');
      final correct = question.options[q.answerOf(i)];
      final lead = question.lead;
      if (lead != null && lead.toLowerCase().contains(correct.toLowerCase())) {
        errors.add('quiz ${quiz.id}: question ${i + 1} lead contains the answer "$correct"');
      }
      for (final n in numberPattern.allMatches(correct).map((x) => x.group(0)!)) {
        final bare = n.replaceAll(RegExp(r'[,.]$'), '');
        if (!sourceText.contains(bare) && !sourceText.contains(bare.replaceAll(',', ''))) {
          errors.add('quiz ${quiz.id}: question ${i + 1} answer figure "$bare" is not in any stored source excerpt');
        }
      }
      for (final option in question.options) {
        if (seededWords.contains(option.trim().toUpperCase())) {
          errors.add('quiz ${quiz.id}: option "$option" is also a seeded word');
        }
      }
    }
  }

  String canonical(Map<String, List<String>> seeds) {
    final keys = seeds.keys.toList()..sort();
    return keys.map((k) => '$k=${(List<String>.of(seeds[k]!)..sort()).join(',')}').join(';');
  }
  if (canonical(m.seeds) != canonical(expectedSeeds)) {
    errors.add('seeds map does not match the puzzles: manifest ${canonical(m.seeds)}, puzzles ${canonical(expectedSeeds)}');
  }
  return errors;
}
