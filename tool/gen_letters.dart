// Generates Letters puzzles, one per date, from the ENABLE word list filtered
// by the 50k frequency list. Deterministic per date.
//
//   dart run tool/gen_letters.dart --from 2026-09-01 --to 2026-12-31 --out content/puzzles [--force]

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:daypencil/content/models.dart';
import 'package:daypencil/core/edition_clock.dart';
import 'package:daypencil/core/game_kind.dart';
import 'package:daypencil/core/puzzle_id.dart';
import 'package:daypencil/engines/letters/letters.dart';

const dictionaryVersion = 'enable1-en50k-2026-09';
const poolMaxRank = 50000;
const pangramMaxRank = 30000;
const commonMaxRank = 20000;
const minAnswers = 20;
const maxAnswers = 80;
const minCommonAnswers = 12;
const minLength = 4;

const blocklist = {
  'anal',
  'anus',
  'arse',
  'arses',
  'bitch',
  'bitches',
  'bitching',
  'boner',
  'boners',
  'chink',
  'chinks',
  'clit',
  'cock',
  'cocks',
  'coon',
  'coons',
  'crap',
  'craps',
  'cunt',
  'cunts',
  'dago',
  'dagos',
  'damn',
  'damned',
  'dick',
  'dicks',
  'dike',
  'dikes',
  'dyke',
  'dykes',
  'fags',
  'faggot',
  'faggots',
  'fuck',
  'fucked',
  'fucker',
  'fuckers',
  'fucking',
  'fucks',
  'gook',
  'gooks',
  'homo',
  'homos',
  'jism',
  'kike',
  'kikes',
  'kraut',
  'krauts',
  'nazi',
  'nazis',
  'negro',
  'negroes',
  'nigga',
  'niggas',
  'nigger',
  'niggers',
  'paki',
  'pakis',
  'penis',
  'penises',
  'piss',
  'pissed',
  'pisses',
  'pissing',
  'porn',
  'porno',
  'prick',
  'pricks',
  'pube',
  'pubes',
  'pussies',
  'pussy',
  'queer',
  'queers',
  'rape',
  'raped',
  'raper',
  'rapes',
  'raping',
  'rapist',
  'rapists',
  'retard',
  'retarded',
  'retards',
  'semen',
  'shit',
  'shits',
  'shitted',
  'shitting',
  'shitty',
  'slut',
  'sluts',
  'spic',
  'spick',
  'spics',
  'tits',
  'titties',
  'titty',
  'tranny',
  'turd',
  'turds',
  'twat',
  'twats',
  'wank',
  'wanked',
  'wanker',
  'wankers',
  'wanking',
  'wanks',
  'wetback',
  'whore',
  'whores',
  'whoring',
  'wog',
  'wogs',
  'wop',
  'wops',
};

int fnv1a(String text) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

int letterBit(int codeUnit) => 1 << (codeUnit - 0x61);

int maskOf(String word) {
  var mask = 0;
  for (final c in word.codeUnits) {
    mask |= letterBit(c);
  }
  return mask;
}

int bitCount(int mask) {
  var n = 0;
  while (mask != 0) {
    mask &= mask - 1;
    n++;
  }
  return n;
}

class PoolWord {
  PoolWord(this.word, this.rank) : mask = maskOf(word);
  final String word;
  final int rank;
  final int mask;
}

class Generated {
  Generated(this.center, this.outer, this.answers, this.pangrams, this.maxScore);
  final String center;
  final String outer;
  final List<String> answers;
  final List<String> pangrams;
  final int maxScore;
}

List<PoolWord> loadPool(Directory dataDir) {
  final enable = File('${dataDir.path}/enable1.txt').readAsLinesSync().map((l) => l.trim()).toSet();
  final lines = File('${dataDir.path}/en_50k.txt').readAsLinesSync();
  final ranks = <String, int>{};
  for (var i = 0; i < lines.length && i < poolMaxRank; i++) {
    final word = lines[i].trim().split(RegExp(r'\s+')).first;
    ranks.putIfAbsent(word, () => i + 1);
  }
  final letters = RegExp(r'^[a-z]+$');
  final pool = <PoolWord>[];
  for (final entry in ranks.entries) {
    final w = entry.key;
    if (w.length < minLength || !letters.hasMatch(w) || blocklist.contains(w) || !enable.contains(w)) continue;
    pool.add(PoolWord(w, entry.value));
  }
  pool.sort((a, b) => a.rank.compareTo(b.rank));
  return pool;
}

List<PoolWord> pangramCandidates(List<PoolWord> pool) =>
    pool.where((p) => p.rank <= pangramMaxRank && bitCount(p.mask) == 7 && !p.word.contains('s')).toList();

Generated? generate(String date, List<PoolWord> pool, List<PoolWord> candidates, Set<int> usedSets) {
  final random = Random(fnv1a('letters-$date'));
  final shuffled = candidates.toList()..shuffle(random);
  for (final candidate in shuffled) {
    final setMask = candidate.mask;
    if (usedSets.contains(setMask)) continue;
    final letters = candidate.word.split('').toSet().toList()..shuffle(random);
    for (final center in letters) {
      final centerBit = letterBit(center.codeUnitAt(0));
      final answers = pool.where((p) => (p.mask & ~setMask) == 0 && (p.mask & centerBit) != 0).toList();
      if (answers.length < minAnswers || answers.length > maxAnswers) continue;
      if (answers.where((p) => p.rank <= commonMaxRank).length < minCommonAnswers) continue;
      final words = answers.map((p) => p.word.toUpperCase()).toList()..sort();
      final upperSet = candidate.word.toUpperCase().split('').toSet();
      final pangrams = words.where((w) => isPangram(w, letters: upperSet)).toList();
      final maxScore = words.fold(0, (sum, w) => sum + scoreWord(w, letters: upperSet));
      final outer =
          (upperSet.toList()
                ..remove(center.toUpperCase())
                ..sort())
              .join();
      usedSets.add(setMask);
      return Generated(center.toUpperCase(), outer, words, pangrams, maxScore);
    }
  }
  return null;
}

int? existingSetMask(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final record = PuzzleRecord.fromJson(json);
    final puzzle = LettersPuzzle.parse(record.payload, record.reveal);
    return maskOf(puzzle.letters.join().toLowerCase());
  } on FormatException {
    return null;
  }
}

void main(List<String> args) {
  String? from;
  String? to;
  var out = 'content/puzzles';
  var force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--from':
        from = args[++i];
      case '--to':
        to = args[++i];
      case '--out':
        out = args[++i];
      case '--force':
        force = true;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(2);
    }
  }
  if (from == null || to == null) {
    stderr.writeln('Usage: dart run tool/gen_letters.dart --from YYYY-MM-DD --to YYYY-MM-DD [--out DIR] [--force]');
    exit(2);
  }
  final start = EditionClock.parseDate(from);
  final end = EditionClock.parseDate(to);
  if (end.isBefore(start)) {
    stderr.writeln('--to is before --from');
    exit(2);
  }

  final scriptDir = File.fromUri(Platform.script).parent;
  final pool = loadPool(Directory('${scriptDir.path}/data'));
  final candidates = pangramCandidates(pool);
  stdout.writeln('Pool: ${pool.length} words, ${candidates.length} pangram candidates');

  final outDir = Directory(out)..createSync(recursive: true);
  final usedSets = <int>{};
  final existing = <String, File>{};
  for (final entity in outDir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final m = RegExp(r'^letters-(\d{4}-\d{2}-\d{2})-en-v1\.json$').firstMatch(name);
    if (m == null) continue;
    existing[m.group(1)!] = entity;
  }

  var written = 0;
  var skipped = 0;
  var failed = 0;
  for (var date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
    final dateText = EditionClock.formatDate(date);
    final id = PuzzleId(game: GameKind.letters, date: date);
    final file = File('${outDir.path}/$id.json');
    if (existing.containsKey(dateText) && !force) {
      final mask = existingSetMask(existing[dateText]!);
      if (mask != null) usedSets.add(mask);
      stdout.writeln('$dateText  skipped, exists');
      skipped++;
      continue;
    }
    final generated = generate(dateText, pool, candidates, usedSets);
    if (generated == null) {
      stderr.writeln('$dateText  FAILED: no letter set satisfied the constraints');
      failed++;
      continue;
    }
    final record = PuzzleRecord(
      id: id,
      locale: 'en-GB',
      contentVersion: 1,
      scoringVersion: 1,
      dictionaryVersion: dictionaryVersion,
      payload: {'center': generated.center, 'outer': generated.outer, 'minLength': minLength},
      reveal: {'answers': generated.answers, 'pangrams': generated.pangrams, 'maxScore': generated.maxScore},
    );
    final text = const JsonEncoder.withIndent('  ').convert(record.toJson());
    final reparsed = PuzzleRecord.fromJson(jsonDecode(text) as Map<String, dynamic>);
    final puzzle = LettersPuzzle.parse(reparsed.payload, reparsed.reveal);
    if (puzzle.answers.length != generated.answers.length || puzzle.maxScore != generated.maxScore) {
      throw StateError('Re-parsed puzzle for $dateText does not match what was generated');
    }
    file.writeAsStringSync('$text\n');
    written++;
    stdout.writeln(
      '$dateText  ${generated.center} + ${generated.outer}  ${puzzle.answers.length} answers  '
      '${puzzle.pangrams.length} pangram${puzzle.pangrams.length == 1 ? '' : 's'}  maxScore ${puzzle.maxScore}',
    );
  }
  stdout.writeln('Written $written, skipped $skipped, failed $failed');
  if (failed > 0) exit(1);
}
