import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/game_kind.dart';
import '../play/play_screen.dart';

/// The news edition for a date: the quiz, then the Front Page.
class NewsEditionScreen extends StatefulWidget {
  const NewsEditionScreen({super.key, required this.dateText});
  final String dateText;

  @override
  State<NewsEditionScreen> createState() => _NewsEditionScreenState();
}

class _NewsEditionScreenState extends State<NewsEditionScreen> {
  late Future<EditionManifest> _future;

  @override
  void initState() {
    super.initState();
    final date = parseRouteDate(widget.dateText);
    final repo = context.read<ContentRepository>();
    _future = date == null ? Future.error(const ContentNotFound('date')) : repo.edition(date);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EditionManifest>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('The edition')),
            body: Center(child: Text('No edition for ${widget.dateText}.', style: Theme.of(context).textTheme.titleMedium)),
          );
        }
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final m = snap.data!;
        final quiz = m.puzzleFor(GameKind.quiz);
        if (quiz == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('The edition')),
            body: Center(child: Text('No quiz on ${m.dateString}.', style: Theme.of(context).textTheme.titleMedium)),
          );
        }
        return PlayScreen(
          puzzleIdText: quiz.toString(),
          nextLabel: 'Read the Front Page',
          onNext: () {
            Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name?.startsWith('/news/') == true);
            context.push('/front/${m.dateString}');
          },
        );
      },
    );
  }
}
