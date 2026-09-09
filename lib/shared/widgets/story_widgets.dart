import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../content/models.dart';
import '../../../core/theme.dart';

/// The dateline above a story-seeded classic, before play.
class StoryTeaser extends StatelessWidget {
  const StoryTeaser({super.key, required this.teaser});

  final String teaser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall,
        children: [
          TextSpan(
            text: "From today's stories · ",
            style: PaperTheme.body(size: 14, weight: 600, color: theme.colorScheme.onSurface),
          ),
          TextSpan(text: teaser),
        ],
      ),
    );
  }
}

/// The sentence from the story that holds the answer, with the answer set
/// in bold, and a link to the story when the edition carries it.
class StoryExcerpt extends StatelessWidget {
  const StoryExcerpt({super.key, required this.excerpt, required this.words, this.story});

  final String excerpt;

  /// Set in bold wherever one occurs as a whole word, in any case.
  final List<String> words;
  final Story? story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = this.story;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(style: theme.textTheme.bodyMedium, children: _spans(PaperTheme.body(weight: 700)))),
        if (story != null) ...[
          const SizedBox(height: 2),
          Text('— ${story.publisher}', style: theme.textTheme.bodySmall),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Read the story'),
            onPressed: () => launchUrl(Uri.parse(story.url), mode: LaunchMode.externalApplication),
          ),
        ],
      ],
    );
  }

  List<InlineSpan> _spans(TextStyle bold) {
    if (words.isEmpty) return [TextSpan(text: excerpt)];
    final pattern = RegExp('(?<![A-Za-z])(?:${words.map(RegExp.escape).join('|')})(?![A-Za-z])', caseSensitive: false);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in pattern.allMatches(excerpt)) {
      if (m.start > last) spans.add(TextSpan(text: excerpt.substring(last, m.start)));
      spans.add(TextSpan(text: m[0], style: bold));
      last = m.end;
    }
    if (last < excerpt.length) spans.add(TextSpan(text: excerpt.substring(last)));
    return spans;
  }
}
