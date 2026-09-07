import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/game_kind.dart';
import '../../core/game_result.dart';
import '../../core/puzzle_id.dart';

const String kSiteBaseUrl = 'https://daypencil.com';

/// Builds share text and challenge links and hands them to the platform
/// share sheet, with clipboard fallbacks where sharing is unavailable.
class ShareService {
  static String puzzleUrl(PuzzleId id, {GameResult? toBeat}) {
    final base = '$kSiteBaseUrl/p/$id';
    if (toBeat == null) return base;
    return '$base?r=${toBeat.challengeCode()}';
  }

  static String dateLabel(PuzzleId id) => DateFormat('d MMM yyyy').format(id.date.toUtc());

  static String titleFor(PuzzleId id) {
    final d = id.difficulty == null ? '' : ' (${id.difficulty!.label})';
    return '${id.game.title}$d';
  }

  /// Spoiler-free result card.
  static String resultText(GameResult result) {
    final id = result.puzzleId;
    final lines = <String>[
      'Daypencil ${titleFor(id)} · ${dateLabel(id)}',
      result.summary(),
      ...result.shareLines,
      puzzleUrl(id),
    ];
    return lines.join('\n');
  }

  /// Same puzzle, with a compact result to beat.
  static String challengeText(GameResult result) {
    final id = result.puzzleId;
    final verb = switch (id.game) {
      GameKind.word => 'Beat my ${result.summary().toLowerCase()}',
      GameKind.quiz => 'Beat my ${result.summary()}',
      GameKind.letters => 'Beat my ${result.points} points',
      GameKind.sudoku || GameKind.crossword => result.seconds == null
          ? 'Can you solve it?'
          : 'Beat my time of ${GameResult.formatSeconds(result.seconds!)}',
    };
    return 'Daypencil ${titleFor(id)} · ${dateLabel(id)}\n$verb\n${puzzleUrl(id, toBeat: result)}';
  }

  /// Returns true when a share sheet or clipboard copy succeeded.
  static Future<bool> share(String text, {String? subject}) async {
    try {
      final outcome = await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      if (outcome.status == ShareResultStatus.unavailable) {
        return copy(text);
      }
      return true;
    } catch (e) {
      debugPrint('share failed, copying instead: $e');
      return copy(text);
    }
  }

  static Future<bool> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }
}
