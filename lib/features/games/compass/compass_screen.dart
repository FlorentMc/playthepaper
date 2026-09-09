import 'package:flutter/material.dart';

import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';

/// Placeholder until the Compass module lands. Keeps the app compiling.
class CompassScreen extends StatelessWidget {
  const CompassScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Compass',
    paragraphs: ['This game is not available yet.'],
  );

  @override
  Widget build(BuildContext context) {
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      difficulty: play.record.difficulty,
      help: help,
      isArchivePlay: play.isArchivePlay,
      puzzleId: play.record.id.toString(),
      child: const Center(child: Text('Coming soon')),
    );
  }
}
