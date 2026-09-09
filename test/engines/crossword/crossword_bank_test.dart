import 'dart:convert';
import 'dart:io';

import 'package:playthepaper/engines/crossword/crossword_generator.dart';
import 'package:playthepaper/engines/crossword/crossword_puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bankJson = jsonDecode(File('content_src/crossword/clues.json').readAsStringSync());
  final bank = CrosswordBank.fromJson(bankJson);
  final dictionary = File('tool/data/enable1.txt').readAsLinesSync().map((w) => w.trim().toUpperCase()).toSet();

  test('every bank answer is an ENABLE word of 3 to 5 letters with a non-empty clue', () {
    expect(bank.entries.length, greaterThanOrEqualTo(380));
    final answers = <String>{};
    for (final e in bank.entries) {
      expect(RegExp(r'^[A-Z]{3,5}$').hasMatch(e.answer), isTrue, reason: e.answer);
      expect(dictionary.contains(e.answer), isTrue, reason: '${e.answer} is not in ENABLE');
      expect(e.clues, isNotEmpty, reason: e.answer);
      for (final c in e.clues) {
        expect(c.trim(), isNotEmpty, reason: e.answer);
        expect(RegExp('\\b${e.answer}\\b').hasMatch(c.toUpperCase()), isFalse, reason: 'clue for ${e.answer} contains the answer');
      }
      expect(answers.add(e.answer), isTrue, reason: '${e.answer} appears twice');
    }
  });

  test('every template is symmetric and numbers cleanly', () {
    for (final t in crosswordTemplates) {
      expect(isRotationallySymmetric(t), isTrue, reason: t.join('/'));
      final entries = deriveEntries(t);
      expect(entries.every((e) => e.length >= 3), isTrue, reason: t.join('/'));
    }
  });

  test('a seeded fill validates and is deterministic', () {
    CrosswordFill? fill;
    var template = 0;
    while (fill == null && template < crosswordTemplates.length) {
      fill = fillGrid(crosswordTemplates[template], bank, SeededRandom(fnv1a('test-fill')));
      template++;
    }
    expect(fill, isNotNull);
    final again = fillGrid(crosswordTemplates[template - 1], bank, SeededRandom(fnv1a('test-fill')));
    expect(again!.solution, fill!.solution);

    final entries = deriveEntries(fill.grid);
    final payload = {
      'size': fill.grid.length,
      'grid': fill.grid,
      'clues': {
        for (final d in Direction.values)
          d.name: [
            for (final e in entries)
              if (e.direction == d) {...e.toJson(), 'clue': 'x'},
          ],
      },
    };
    final puzzle = CrosswordPuzzle.parse(payload, {'solution': fill.solution});
    final answers = answersOf(puzzle);
    expect(answers.toSet().length, answers.length, reason: 'no duplicate answers within a puzzle');
    for (final a in answers) {
      expect(dictionary.contains(a), isTrue, reason: a);
    }
  });

  test('every generated crossword in content/ parses', () {
    final files = Directory('content/puzzles').listSync().whereType<File>().where((f) => f.path.contains('/crossword-'));
    expect(files.length, greaterThan(0));
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final puzzle = CrosswordPuzzle.parse(json['payload'] as Map<String, dynamic>, json['reveal'] as Map<String, dynamic>);
      final answers = answersOf(puzzle);
      expect(answers.toSet().length, answers.length, reason: f.path);
      for (final e in puzzle.entries) {
        expect(e.clue.trim(), isNotEmpty, reason: '${f.path} ${e.label}');
      }
    }
  });
}
