import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/game_kind.dart';
import '../../core/game_result.dart';
import '../../core/puzzle_id.dart';

const String kSiteBaseUrl = 'https://playthepaper.com';

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
      'Play the Paper ${titleFor(id)} · ${dateLabel(id)}',
      result.summary(),
      ...result.shareLines,
      puzzleUrl(id),
    ];
    return lines.join('\n');
  }

  /// Same puzzle, with a compact result to beat.
  static String challengeText(GameResult result) {
    final id = result.puzzleId;
    final String verb;
    if (id.game == GameKind.word || id.game == GameKind.quiz) {
      verb = 'Beat my ${result.summary().toLowerCase()}';
    } else if (id.game == GameKind.letters) {
      verb = 'Beat my ${result.points} points';
    } else if (id.game.isTimed) {
      verb = result.seconds == null ? 'Can you solve it?' : 'Beat my time of ${GameResult.formatSeconds(result.seconds!)}';
    } else {
      verb = 'Beat my ${result.summary()}';
    }
    return 'Play the Paper ${titleFor(id)} · ${dateLabel(id)}\n$verb\n${puzzleUrl(id, toBeat: result)}';
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
