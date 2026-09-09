import 'package:flutter/material.dart';

import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';

/// Placeholder until the Nonogram module lands. Keeps the app compiling.
class NonogramScreen extends StatelessWidget {
  const NonogramScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'Nonogram',
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
