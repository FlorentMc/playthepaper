import 'dart:convert';
import 'dart:io';

/// Shared helpers for the content tools. Keep this file dependency-free
/// beyond dart:io so every tool can import it.

const JsonEncoder prettyJson = JsonEncoder.withIndent('  ');

/// Stable 32-bit FNV-1a hash. `String.hashCode` is not stable across
/// platforms, so every seed derives from this instead.
int fnv1a(String input) {
  var hash = 0x811C9DC5;
  for (final unit in utf8.encode(input)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

String formatDate(DateTime d) {
  final u = d.toUtc();
  return '${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

DateTime parseDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) throw FormatException('Bad date: $s');
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (formatDate(d) != s) throw FormatException('Bad date: $s');
  return d;
}

Iterable<DateTime> dateRange(DateTime from, DateTime to) sync* {
  for (var d = from; !d.isAfter(to); d = DateTime.utc(d.year, d.month, d.day + 1)) {
    yield d;
  }
}

Map<String, String> parseArgs(List<String> args, {Map<String, String> defaults = const {}}) {
  final out = Map<String, String>.from(defaults);
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) throw ArgumentError('Unexpected argument: $a');
    final key = a.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[key] = args[++i];
    } else {
      out[key] = 'true';
    }
  }
  return out;
}

void writeJsonFile(String path, Object json) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('${prettyJson.convert(json)}\n');
}

Map<String, dynamic> readJsonFile(String path) {
  final json = jsonDecode(File(path).readAsStringSync());
  if (json is! Map<String, dynamic>) throw FormatException('$path is not a JSON object');
  return json;
}

Never fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}
