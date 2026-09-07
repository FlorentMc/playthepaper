import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../content/content_repository.dart';
import '../../core/theme.dart';
import 'edition_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final editions = context.watch<EditionController>();
    final theme = Theme.of(context);
    final manifest = editions.today;

    return Scaffold(
      appBar: AppBar(
        title: Text('Daypencil', style: DaypencilTheme.display(size: 26, color: theme.colorScheme.onSurface)),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month_outlined), tooltip: 'Archive', onPressed: () => context.push('/archive')),
          IconButton(icon: const Icon(Icons.bar_chart), tooltip: 'Statistics', onPressed: () => context.push('/stats')),
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () => context.push('/settings')),
        ],
      ),
      body: SafeArea(
        child: manifest == null
            ? Center(
                child: editions.loading
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('No edition could be loaded.', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('Check your connection and try again.', style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 16),
                            FilledButton(onPressed: editions.load, child: const Text('Retry')),
                          ],
                        ),
                      ),
              )
            : RefreshIndicator(
                onRefresh: editions.load,
                child: EditionView(manifest: manifest, isToday: manifest.date == editions.todayDate),
              ),
      ),
    );
  }
}
