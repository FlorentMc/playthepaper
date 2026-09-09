import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the shipped typefaces so layout tests measure real glyphs rather
/// than the test framework's substitute font.
Future<void> loadRealFonts() async {
  for (final entry in {
    'Playfair Display': 'assets/fonts/PlayfairDisplay.ttf',
    'Source Sans 3': 'assets/fonts/SourceSans3.ttf',
  }.entries) {
    final bytes = File(entry.value).readAsBytesSync();
    final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}
