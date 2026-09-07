import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../content/content_repository.dart';
import '../../content/models.dart';
import 'edition_view.dart';

/// An archived edition, reached from the archive or a dated link.
class EditionScreen extends StatefulWidget {
  const EditionScreen({super.key, required this.dateText});
  final String dateText;

  @override
  State<EditionScreen> createState() => _EditionScreenState();
}

class _EditionScreenState extends State<EditionScreen> {
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
    final editions = context.watch<EditionController>();
    final date = parseRouteDate(widget.dateText);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(date == null ? 'Edition' : DateFormat('d MMMM yyyy').format(date.toUtc())),
      ),
      body: SafeArea(
        child: FutureBuilder<EditionManifest>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No edition for ${widget.dateText}.', style: Theme.of(context).textTheme.titleMedium),
                ),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return EditionView(manifest: snap.data!, isToday: snap.data!.date == editions.todayDate);
          },
        ),
      ),
    );
  }
}
