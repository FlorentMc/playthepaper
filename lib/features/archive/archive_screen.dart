import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../content/content_repository.dart';
import '../../content/models.dart';
import '../../core/edition_clock.dart';
import '../../core/theme.dart';

/// Every edition on record, newest first. Archive play is free and labelled
/// with its original date.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  late Future<ContentIndex> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ContentRepository>().index();
  }

  @override
  Widget build(BuildContext context) {
    final editions = context.watch<EditionController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Archive')),
      body: SafeArea(
        child: FutureBuilder<ContentIndex>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('The archive is not available offline yet.', style: theme.textTheme.titleMedium));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final today = editions.todayDate;
            final dates = snap.data!.dates.where((d) => !d.isAfter(today)).toList().reversed.toList();
            if (dates.isEmpty) {
              return Center(child: Text('Nothing in the archive yet.', style: theme.textTheme.titleMedium));
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: dates.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, i) {
                final d = dates[i];
                final isToday = d == today;
                return ListTile(
                  title: Text(
                    DateFormat('EEEE d MMMM yyyy').format(d.toUtc()),
                    style: DaypencilTheme.display(size: 18, color: theme.colorScheme.onSurface),
                  ),
                  subtitle: Text(isToday ? 'Today' : 'Archive', style: theme.textTheme.bodySmall),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => isToday ? context.go('/') : context.push('/e/${EditionClock.formatDate(d)}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
