import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/game_kind.dart';
import '../../core/theme.dart';
import '../../features/about/about_screen.dart';
import '../../features/play/play_context.dart';

/// The common frame for every game: title, edition date, help, and a body.
/// Shows the help sheet automatically the first time a game is opened.
class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.game,
    required this.date,
    required this.help,
    required this.child,
    this.difficulty,
    this.actions = const [],
    this.isArchivePlay = false,
    this.helpSeenKey,
    this.bottom,
    this.puzzleId,
  });

  final GameKind game;
  final DateTime date;
  final Difficulty? difficulty;
  final GameHelp help;
  final Widget child;
  final List<Widget> actions;
  final bool isArchivePlay;

  /// Overrides the key used to remember that help was shown.
  final String? helpSeenKey;
  final PreferredSizeWidget? bottom;

  /// Included in a problem report.
  final String? puzzleId;

  static final Set<String> _helpShownThisSession = {};

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  @override
  void initState() {
    super.initState();
    final key = widget.helpSeenKey ?? widget.game.slug;
    if (GameShell._helpShownThisSession.add(key)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showHelpSheet(context, widget.help);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM yyyy').format(widget.date.toUtc());
    final subtitle = [
      if (widget.difficulty != null) widget.difficulty!.label,
      dateLabel,
      if (widget.isArchivePlay) 'Archive',
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.game.title),
            Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        actions: [
          ...widget.actions,
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How to play',
            onPressed: () => showHelpSheet(context, widget.help),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'report') reportProblem(context, puzzleId: widget.puzzleId);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'report', child: Text('Report a problem')),
            ],
          ),
        ],
        bottom: widget.bottom,
      ),
      body: SafeArea(child: widget.child),
    );
  }
}

Future<void> showHelpSheet(BuildContext context, GameHelp help) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(help.title, style: DaypencilTheme.display(size: 24, color: theme.colorScheme.onSurface)),
            const SizedBox(height: 12),
            for (final p in help.paragraphs) ...[
              Text(p, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 10),
            ],
            if (help.example != null) ...[
              const SizedBox(height: 8),
              help.example!(context),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
          ],
        ),
      );
    },
  );
}

/// A thin newspaper rule.
class Rule extends StatelessWidget {
  const Rule({super.key, this.thick = false});
  final bool thick;

  @override
  Widget build(BuildContext context) =>
      Container(height: thick ? 2 : 1, color: thick ? Theme.of(context).colorScheme.onSurface : context.gameColors.rule);
}
