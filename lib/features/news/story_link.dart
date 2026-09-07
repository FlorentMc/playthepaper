import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/game_result.dart';
import '../play/play_context.dart';

/// The URL a news game's reveal should point at: the story if the edition
/// supplied one, else the puzzle's first source.
String? storyUrlFor(PlayContext play) => play.story?.url ?? play.record.sources.firstOrNull?.url;

/// "Read the story" as an external link, with the publisher when known.
class StoryLink extends StatelessWidget {
  const StoryLink({super.key, required this.url, this.publisher, this.label = 'Read the story'});

  final String? url;
  final String? publisher;
  final String label;

  @override
  Widget build(BuildContext context) {
    final uri = url == null ? null : Uri.tryParse(url!);
    final text = publisher == null ? label : '$publisher · $label';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(text),
        onPressed: uri == null ? null : () => launchUrl(uri, mode: LaunchMode.externalApplication),
      ),
    );
  }
}

/// A friend's result to beat, shown above the board when a challenge link
/// opened the puzzle.
class FriendLine extends StatelessWidget {
  const FriendLine({super.key, required this.challenge});

  final GameResult? challenge;

  @override
  Widget build(BuildContext context) {
    if (challenge == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Friend: ${challenge!.summary()}', style: theme.textTheme.labelMedium)),
        ],
      ),
    );
  }
}
