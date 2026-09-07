import 'package:flutter/material.dart';

import '../../../shared/widgets/game_shell.dart';
import '../../play/play_context.dart';

/// Placeholder until the Quiz module lands. Keeps the app compiling.
class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key, required this.play});

  final PlayContext play;

  static const GameHelp help = GameHelp(
    title: 'The Quiz',
    paragraphs: ['This game is not available yet.'],
  );

  @override
  Widget build(BuildContext context) {
    return GameShell(
      game: play.record.game,
      date: play.record.date,
      help: help,
      isArchivePlay: play.isArchivePlay,
      child: const Center(child: Text('Coming soon')),
    );
  }
}
