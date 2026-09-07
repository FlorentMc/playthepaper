import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/edition_clock.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/engines/word/word_engine.dart';

/// Generates Daily Word puzzle files for a date range.
///
///   dart run tool/gen_word.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]
///
/// Answers are common six-letter words. The schedule is a fixed shuffle of
/// the candidate list, so a date always yields the same word as long as the
/// word lists and filters below do not change.

const dictionaryVersion = 'enable1-2026-09';
const enablePath = 'tool/data/enable1.txt';
const frequencyPath = 'tool/data/en_50k.txt';
const guessListPath = 'assets/dictionaries/words6_en.txt';
const wordLength = 6;
const maxGuesses = 6;
const preferredRank = 25000;
const relaxedRank = 40000;
const minCandidates = 600;
const scheduleSeed = 20260901;
final scheduleEpoch = DateTime.utc(2026, 9, 1);

const blocklist = {
  'nigger',
  'nigras',
  'faggot',
  'honkey',
  'whitey',
  'tranny',
  'retard',
  'spooks',
  'fucked',
  'fucker',
  'shitty',
  'wanker',
  'bitchy',
  'pissed',
  'cummed',
  'boners',
};

void main(List<String> args) {
  final options = _parseArgs(args);
  final from = EditionClock.parseDate(options['from']!);
  final to = EditionClock.parseDate(options['to']!);
  final outDir = Directory(options['out']!);
  final force = options.containsKey('force');
  if (to.isBefore(from)) _fail('--to is before --from');

  final enable = _readWords(enablePath);
  final guessList = _readWords(guessListPath, uppercase: true);
  final candidates = buildCandidates(enable: enable, rankOf: _readRanks(frequencyPath));
  final schedule = List<String>.from(candidates)..shuffle(Random(scheduleSeed));

  outDir.createSync(recursive: true);
  var written = 0;
  var skipped = 0;
  for (var date = from; !date.isAfter(to); date = date.add(const Duration(days: 1))) {
    final answer = answerFor(schedule, date).toUpperCase();
    if (!guessList.contains(answer)) _fail('Answer $answer is not in $guessListPath');
    final id = PuzzleId(game: GameKind.word, date: date);
    final file = File('${outDir.path}/$id.json');
    if (file.existsSync() && !force) {
      skipped++;
      continue;
    }
    final puzzle = WordPuzzle(length: wordLength, firstLetter: answer[0], maxGuesses: maxGuesses, answer: answer);
    final record = PuzzleRecord(
      id: id,
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      dictionaryVersion: dictionaryVersion,
      payload: puzzle.toPayload(),
      reveal: puzzle.toReveal(),
    );
    final json = record.toJson();
    final check = PuzzleRecord.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
    if (WordPuzzle.parse(check.payload, check.reveal) != puzzle) _fail('Round trip failed for $id');
    file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
    written++;
  }

  stdout.writeln(
    'Candidates: ${candidates.length} (${candidates.first} … ${candidates.last} sorted, '
    'schedule seed $scheduleSeed)',
  );
  stdout.writeln('Range: ${EditionClock.formatDate(from)} to ${EditionClock.formatDate(to)}');
  stdout.writeln('Written: $written, skipped existing: $skipped, out: ${outDir.path}');
}

/// The sorted candidate answers: common six-letter ENABLE words, without
/// plurals, trivial inflections or offensive words.
List<String> buildCandidates({required Set<String> enable, required Map<String, int> rankOf}) {
  List<String> filter(int maxRank) => [
    for (final word in enable)
      if (word.length == wordLength &&
          RegExp(r'^[a-z]+$').hasMatch(word) &&
          (rankOf[word] ?? 1 << 30) <= maxRank &&
          !blocklist.contains(word) &&
          !_isInflection(word, enable))
        word,
  ]..sort();
  var candidates = filter(preferredRank);
  if (candidates.length < minCandidates) {
    stderr.writeln('Only ${candidates.length} candidates at rank $preferredRank; relaxing to $relaxedRank');
    candidates = filter(relaxedRank);
  }
  if (candidates.length < minCandidates) _fail('Only ${candidates.length} candidates after relaxing the rank');
  return candidates;
}

bool _isInflection(String word, Set<String> enable) {
  if (word.endsWith('s') && enable.contains(word.substring(0, 5))) return true;
  if (word.endsWith('es') && enable.contains(word.substring(0, 4))) return true;
  if ((word.endsWith('ies') || word.endsWith('ied')) && enable.contains('${word.substring(0, 3)}y')) return true;
  if (word.endsWith('ed')) {
    final stem = word.substring(0, 4);
    if (enable.contains(stem) || enable.contains('${stem}e')) return true;
    if (stem[3] == stem[2] && enable.contains(stem.substring(0, 3))) return true;
  }
  if (word.endsWith('ing')) {
    final stem = word.substring(0, 3);
    if (enable.contains(stem) || enable.contains('${stem}e')) return true;
  }
  return false;
}

String answerFor(List<String> schedule, DateTime date) {
  final days = date.toUtc().difference(scheduleEpoch).inDays;
  return schedule[days % schedule.length];
}

Set<String> _readWords(String path, {bool uppercase = false}) {
  final file = File(path);
  if (!file.existsSync()) _fail('Missing $path');
  return {
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty) uppercase ? line.trim().toUpperCase() : line.trim().toLowerCase(),
  };
}

/// Word to 1-based rank, most frequent first. Lines are "word count".
Map<String, int> _readRanks(String path) {
  final file = File(path);
  if (!file.existsSync()) _fail('Missing $path');
  final ranks = <String, int>{};
  var rank = 0;
  for (final line in file.readAsLinesSync()) {
    final word = line.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (word.isEmpty) continue;
    rank++;
    ranks.putIfAbsent(word, () => rank);
  }
  return ranks;
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) _fail('Unexpected argument: $arg');
    final name = arg.substring(2);
    if (name == 'force') {
      options[name] = 'true';
    } else if (i + 1 < args.length) {
      options[name] = args[++i];
    } else {
      _fail('Missing value for --$name');
    }
  }
  for (final required in ['from', 'to', 'out']) {
    if (!options.containsKey(required)) {
      _fail('Usage: dart run tool/gen_word.dart --from YYYY-MM-DD --to YYYY-MM-DD --out DIR [--force]');
    }
  }
  return options;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
