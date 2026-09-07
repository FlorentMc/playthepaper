import 'dart:io';

import 'package:daypencil/core/puzzle_id.dart';

/// Writes one static HTML page per puzzle under `<content>/share/<id>.html`.
///
/// Each page is the web shell with puzzle-specific title and Open Graph tags,
/// so a shared link previews as "Daypencil Mini Crossword · 8 September 2026"
/// while still booting the app at `/p/<id>` for a human who taps it. Nginx
/// serves these for `/p/<id>` when present and falls back to the app shell.
int writeSharePages(String content, String indexHtmlPath) {
  final template = File(indexHtmlPath).readAsStringSync().replaceAll(r'$FLUTTER_BASE_HREF', '/');
  final dir = Directory('$content/share')..createSync(recursive: true);
  final existing = dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toSet();
  var written = 0;
  for (final f in Directory('$content/puzzles').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.json')) continue;
    final id = PuzzleId.tryParse(name.substring(0, name.length - 5));
    if (id == null) continue;
    final out = '$content/share/$id.html';
    if (existing.contains('$id.html')) continue;
    final title = 'Daypencil ${_title(id)} · ${_longDate(id.date)}';
    final description = 'Play the same puzzle and compare results. Free, no account needed.';
    final html = template
        .replaceFirst(RegExp(r'<title>[^<]*</title>'), '<title>${_esc(title)}</title>')
        .replaceFirst(RegExp(r'<meta property="og:title" content="[^"]*">'),
            '<meta property="og:title" content="${_esc(title)}">')
        .replaceFirst(RegExp(r'<meta property="og:description" content="[^"]*">'),
            '<meta property="og:description" content="${_esc(description)}">')
        .replaceFirst(RegExp(r'<meta name="description" content="[^"]*">'),
            '<meta name="description" content="${_esc(description)}">')
        .replaceFirst('<link rel="manifest" href="manifest.json">',
            '<meta property="og:url" content="https://daypencil.com/p/$id">\n  <link rel="manifest" href="manifest.json">');
    File(out).writeAsStringSync(html);
    written++;
  }
  return written;
}

String _title(PuzzleId id) =>
    id.difficulty == null ? id.game.title : '${id.game.title} (${id.difficulty!.label})';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String _longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');
