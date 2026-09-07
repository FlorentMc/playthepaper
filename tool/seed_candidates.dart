import 'dart:io';

import 'package:daypencil/engines/letters/letters.dart';
import 'package:daypencil/engines/word/word_engine.dart';

import '_common.dart';

/// Lists the words in a story text that qualify as seeds, so the publisher
/// never guesses: Daily Word answers (six letters, in the shipped guess
/// list), Letters pangrams (seven distinct letters, in the pool) and
/// crossword answers (three to five letters, in ENABLE).
///
///   dart run tool/seed_candidates.dart /tmp/story.txt [more files...]
void main(List<String> args) {
  if (args.isEmpty) fail('usage: dart run tool/seed_candidates.dart <text file> [...]');
  final enable = File('tool/data/enable1.txt').readAsLinesSync().map((l) => l.trim().toLowerCase()).where((l) => l.isNotEmpty).toSet();
  final ranked = File('tool/data/en_50k.txt').readAsLinesSync().map((l) => l.trim().split(RegExp(r'\s+')).first).toList();
  final rankOf = <String, int>{for (var i = 0; i < ranked.length; i++) ranked[i]: i + 1};
  final guessList = File('assets/dictionaries/words6_en.txt').readAsLinesSync().map((l) => l.trim().toUpperCase()).toSet();

  final word = WordGenerator(
    candidates: WordGenerator.buildCandidates(enable: enable, rankOf: rankOf),
    guessList: guessList,
  );
  final letters = LettersGenerator(pool: LettersGenerator.buildPool(enable: enable, rankedWords: ranked));

  for (final path in args) {
    final text = File(path).readAsStringSync();
    stdout.writeln('== $path');
    final words = word.candidatesIn(text);
    final sixLetter = {
      for (final m in RegExp(r"\b[A-Za-z]{6}\b").allMatches(text))
        if (guessList.contains(m.group(0)!.toUpperCase())) m.group(0)!.toUpperCase(),
    };
    stdout.writeln('word (common, best first): ${words.isEmpty ? '-' : words.join(' ')}');
    final rest = sixLetter.difference(words.toSet());
    if (rest.isNotEmpty) stdout.writeln('word (valid, less common): ${rest.join(' ')}');
    final pangrams = letters.pangramCandidatesIn(text);
    stdout.writeln('letters pangram: ${pangrams.isEmpty ? '- (use null)' : pangrams.join(' ')}');
    final short = <String>{};
    for (final m in RegExp(r"\b[A-Za-z]{3,5}\b").allMatches(text)) {
      final w = m.group(0)!.toLowerCase();
      if (enable.contains(w) && (rankOf[w] ?? 999999) <= 30000) short.add(w.toUpperCase());
    }
    final sorted = short.toList()..sort((a, b) => b.length.compareTo(a.length) != 0 ? b.length.compareTo(a.length) : a.compareTo(b));
    stdout.writeln('crossword (3-5 letters, common): ${sorted.isEmpty ? '-' : sorted.join(' ')}');
  }
}
