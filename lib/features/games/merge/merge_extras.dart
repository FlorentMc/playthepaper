import 'dart:convert';

import '../../../engines/merge/merge.dart';
import '../../../storage/local_store.dart';

/// Everything Merge keeps outside puzzle progress, under `LocalStore.extra`:
/// the unlimited game, the best score made in it, and the last few finished
/// daily boards so a completed day can be reopened and looked over. None of
/// it is a result; unlimited play is never recorded.
class MergeExtras {
  const MergeExtras({this.unlimited, this.bestUnlimited = 0, this.finished = const {}});

  static const String key = 'merge';

  /// How many finished daily boards are kept, oldest dropped first.
  static const int keepFinished = 6;

  final Map<String, dynamic>? unlimited;
  final int bestUnlimited;

  /// Puzzle id to the saved final state of that day.
  final Map<String, Map<String, dynamic>> finished;

  /// Reads the store. Anything malformed is treated as absent so a bad write
  /// can never stop the game opening.
  static MergeExtras load(LocalStore store) {
    final raw = store.extra(key);
    if (raw == null) return const MergeExtras();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const MergeExtras();
      final rawFinished = json['finished'];
      final finished = <String, Map<String, dynamic>>{};
      if (rawFinished is Map) {
        for (final e in rawFinished.entries) {
          if (e.value is Map) finished[e.key as String] = Map<String, dynamic>.from(e.value as Map);
        }
      }
      final best = json['bestUnlimited'];
      return MergeExtras(
        unlimited: json['unlimited'] is Map ? Map<String, dynamic>.from(json['unlimited'] as Map) : null,
        bestUnlimited: best is int && best >= 0 ? best : 0,
        finished: finished,
      );
    } on FormatException {
      return const MergeExtras();
    }
  }

  Future<void> save(LocalStore store) => store.setExtra(key, jsonEncode(toJson()));

  Map<String, dynamic> toJson() => {
        if (unlimited != null) 'unlimited': unlimited,
        'bestUnlimited': bestUnlimited,
        if (finished.isNotEmpty) 'finished': finished,
      };

  /// The saved unlimited game, or null when there is none to resume.
  MergeState? unlimitedState() => _state(unlimited);

  /// The board a finished daily ended on, or null when it is no longer kept.
  MergeState? finishedState(String puzzleId) => _state(finished[puzzleId]);

  static MergeState? _state(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return MergeState.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  MergeExtras withUnlimited(MergeState state) => MergeExtras(
        unlimited: state.toJson(),
        bestUnlimited: state.score > bestUnlimited ? state.score : bestUnlimited,
        finished: finished,
      );

  MergeExtras withFinished(String puzzleId, MergeState state) {
    final next = <String, Map<String, dynamic>>{...finished}..remove(puzzleId);
    next[puzzleId] = state.toJson();
    while (next.length > keepFinished) {
      next.remove(next.keys.first);
    }
    return MergeExtras(unlimited: unlimited, bestUnlimited: bestUnlimited, finished: next);
  }
}
