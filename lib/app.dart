import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'content/content_repository.dart';
import 'core/edition_clock.dart';
import 'core/puzzle_id.dart';
import 'core/theme.dart';
import 'features/about/about_screen.dart';
import 'features/archive/archive_screen.dart';
import 'features/home/edition_screen.dart';
import 'features/home/home_screen.dart';
import 'features/news/front_page_screen.dart';
import 'features/news/news_edition_screen.dart';
import 'features/play/play_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stats/stats_screen.dart';
import 'storage/local_store.dart';

class DaypencilApp extends StatefulWidget {
  const DaypencilApp({super.key, required this.store, required this.repository});

  final LocalStore store;
  final ContentRepository repository;

  @override
  State<DaypencilApp> createState() => _DaypencilAppState();
}

class _DaypencilAppState extends State<DaypencilApp> {
  late final EditionController _editions;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _editions = EditionController(repository: widget.repository)..load();
    _router = buildRouter();
  }

  @override
  void dispose() {
    _editions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LocalStore>.value(value: widget.store),
        ChangeNotifierProvider<Settings>.value(value: widget.store.settings),
        Provider<ContentRepository>.value(value: widget.repository),
        ChangeNotifierProvider<EditionController>.value(value: _editions),
      ],
      child: Consumer<Settings>(
        builder: (context, settings, _) => MaterialApp.router(
          title: 'Daypencil',
          debugShowCheckedModeBanner: false,
          theme: DaypencilTheme.light(),
          darkTheme: DaypencilTheme.dark(),
          themeMode: settings.themeMode,
          routerConfig: _router,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(disableAnimations: media.disableAnimations || settings.reducedMotion),
              child: child!,
            );
          },
        ),
      ),
    );
  }
}

GoRouter buildRouter({String initialLocation = '/'}) {
  Page<void> page(GoRouterState state, Widget child) =>
      MaterialPage<void>(key: state.pageKey, child: child);

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', pageBuilder: (c, s) => page(s, const HomeScreen())),
      GoRoute(
        path: '/p/:id',
        pageBuilder: (c, s) => page(
          s,
          PlayScreen(
            puzzleIdText: s.pathParameters['id']!,
            challengeCode: s.uri.queryParameters['r'],
          ),
        ),
      ),
      GoRoute(path: '/play/:id', redirect: (c, s) => '/p/${s.pathParameters['id']}${s.uri.query.isEmpty ? '' : '?${s.uri.query}'}'),
      GoRoute(path: '/e/:date', pageBuilder: (c, s) => page(s, EditionScreen(dateText: s.pathParameters['date']!))),
      GoRoute(path: '/news/:date', pageBuilder: (c, s) => page(s, NewsEditionScreen(dateText: s.pathParameters['date']!))),
      GoRoute(path: '/front/:date', pageBuilder: (c, s) => page(s, FrontPageScreen(dateText: s.pathParameters['date']!))),
      GoRoute(path: '/archive', pageBuilder: (c, s) => page(s, const ArchiveScreen())),
      GoRoute(path: '/stats', pageBuilder: (c, s) => page(s, const StatsScreen())),
      GoRoute(path: '/settings', pageBuilder: (c, s) => page(s, const SettingsScreen())),
      GoRoute(path: '/about', pageBuilder: (c, s) => page(s, const AboutScreen())),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('That page does not exist.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => context.go('/'), child: const Text('Back to today')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Helpers used by routes.
DateTime? parseRouteDate(String text) {
  try {
    return EditionClock.parseDate(text);
  } on FormatException {
    return null;
  }
}

PuzzleId? parseRoutePuzzle(String text) => PuzzleId.tryParse(text);
