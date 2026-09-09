import 'package:flutter/material.dart';

import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';

/// Placeholder until the Bridges module lands. Keeps the app compiling.
class BridgesScreen extends StatelessWidget {
  const BridgesScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Bridges',
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
