import 'package:flutter/widgets.dart';

import '../../content/models.dart';
import '../../core/game_result.dart';
import '../../storage/local_store.dart';
import '../results/result_screen.dart';

/// Everything a game screen needs beyond its puzzle: where to persist state,
/// an optional friend's result to beat, and what happens when it is done.
class PlayContext {
  const PlayContext({
    required this.store,
    required this.record,
    this.challenge,
    this.story,
    this.isArchivePlay = false,
    this.onCompleted,
    this.nextLabel,
    this.onNext,
  });

  final LocalStore store;
  final PuzzleRecord record;

  /// A friend's result carried by a challenge link, if any.
  final GameResult? challenge;

  /// The story behind a news puzzle, for the reveal and the Front Page.
  final Story? story;

  /// True when the puzzle is played from the archive after its own date.
  final bool isArchivePlay;

  /// Called once with the final result, after it has been saved.
  final void Function(GameResult result)? onCompleted;

  /// When set, the result screen shows a primary button that continues a
  /// flow (the news edition moves to the next round).
  final String? nextLabel;
  final VoidCallback? onNext;

  Map<String, dynamic>? loadProgress() => store.progress(record.id);
  Future<void> saveProgress(Map<String, dynamic> state) => store.saveProgress(record.id, state);
  GameResult? existingResult() => store.result(record.id);

  /// Saves the result, notifies the flow, and shows the result screen.
  /// Games call this exactly once when play ends.
  Future<void> complete(BuildContext context, GameResult result, {String? revealTitle, Widget? reveal}) async {
    await store.saveResult(result);
    onCompleted?.call(result);
    if (!context.mounted) return;
    await showResult(context, result, revealTitle: revealTitle, reveal: reveal);
  }

  /// Shows the result screen for an already-completed puzzle.
  Future<void> showResult(BuildContext context, GameResult result, {String? revealTitle, Widget? reveal}) {
    return ResultScreen.show(
      context,
      result: result,
      store: store,
      challenge: challenge,
      revealTitle: revealTitle,
      reveal: reveal,
      nextLabel: nextLabel,
      onNext: onNext,
    );
  }
}

/// A game screen builder. Each game registers one in [GameRegistry].
typedef GameScreenBuilder = Widget Function(BuildContext context, PlayContext play);

/// Static help copy for a game, shown on first play and from the help button.
class GameHelp {
  const GameHelp({required this.title, required this.paragraphs, this.example});

  final String title;
  final List<String> paragraphs;

  /// Optional widget builder for a short worked example.
  final WidgetBuilder? example;
}
