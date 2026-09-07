import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../shared/widgets/game_shell.dart';

const String kSupportEmail = 'hello@daypencil.com';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            Text('Daypencil', style: DaypencilTheme.display(size: 30, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 6),
            Text('A free daily puzzle paper.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(
              'Four familiar games every day, plus a short playable edition about interesting things '
              'happening in the world. Everything is free. Your progress stays on this device.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            const Rule(thick: true),
            const SizedBox(height: 12),
            Text('WORD POLICY', style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(
              'Letters and Daily Word accept words from the public-domain ENABLE word list, with '
              'proper nouns, abbreviations, hyphenated and apostrophe words excluded. Each puzzle '
              'records the dictionary version it was built with, so later vocabulary changes never '
              'alter an older puzzle\'s score. British and American spellings in the list are both accepted.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('THE NEWS EDITION', style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(
              'Stories are chosen from a small set of sources covering science, culture, technology, '
              'nature, discoveries and everyday life. War, violent crime, disasters and partisan politics '
              'are excluded. Every reveal links to the original article. The Correct dispatch always '
              'contains one deliberate alteration; it is a puzzle, not a report.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('CREDITS', style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(
              'Typefaces: Playfair Display and Source Sans 3, SIL Open Font License. '
              'Coastlines: Natural Earth, public domain. Word list: ENABLE, public domain.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline),
              label: const Text('Report a problem'),
              onPressed: () => reportProblem(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a prepared email with the puzzle id and version filled in.
Future<void> reportProblem(BuildContext context, {String? puzzleId}) async {
  final subject = puzzleId == null ? 'Daypencil problem' : 'Daypencil problem: $puzzleId';
  final body = puzzleId == null ? 'What went wrong:\n' : 'Puzzle: $puzzleId\nWhat went wrong:\n';
  final uri = Uri(
    scheme: 'mailto',
    path: kSupportEmail,
    query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );
  final ok = await launchUrl(uri);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Email $kSupportEmail with the puzzle id')));
  }
}
