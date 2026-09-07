import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The list of valid six-letter guesses, loaded from the bundle once.
class WordDictionary {
  WordDictionary._();

  static const asset = 'assets/dictionaries/words6_en.txt';

  /// When set, replaces the bundled list. Tests only.
  @visibleForTesting
  static Set<String>? debugOverride;

  static Future<Set<String>>? _cached;

  static Future<Set<String>> load() {
    final override = debugOverride;
    if (override != null) return Future.value(override);
    return _cached ??= rootBundle
        .loadString(asset)
        .then(
          (text) => {
            for (final line in text.split('\n'))
              if (line.trim().isNotEmpty) line.trim().toUpperCase(),
          },
        );
  }
}
