import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../storage/local_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final settings = context.watch<Settings>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(title: Text('Appearance', style: theme.textTheme.labelSmall)),
            RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (m) => store.updateSettings(themeMode: m),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(value: ThemeMode.system, title: Text('Match device')),
                  RadioListTile<ThemeMode>(value: ThemeMode.light, title: Text('Light')),
                  RadioListTile<ThemeMode>(value: ThemeMode.dark, title: Text('Dark')),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Reduce motion'),
              subtitle: const Text('Shorter transitions and no decorative animation'),
              value: settings.reducedMotion,
              onChanged: (v) => store.updateSettings(reducedMotion: v),
            ),
            const Divider(),
            ListTile(title: Text('Play', style: theme.textTheme.labelSmall)),
            SwitchListTile(
              title: const Text('Show timers'),
              subtitle: const Text('Crossword and Sudoku time is always recorded, never required'),
              value: settings.showTimers,
              onChanged: (v) => store.updateSettings(showTimers: v),
            ),
            SwitchListTile(
              title: const Text('Sudoku mistake check'),
              subtitle: const Text('Mark a number that conflicts with the solution'),
              value: settings.sudokuMistakeCheck,
              onChanged: (v) => store.updateSettings(sudokuMistakeCheck: v),
            ),
            const Divider(),
            ListTile(title: Text('Your data', style: theme.textTheme.labelSmall)),
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Export progress'),
              subtitle: const Text('Copies your history to the clipboard as text'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: store.exportJson()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export copied')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Import progress'),
              subtitle: const Text('Paste an export from another device'),
              onTap: () => _import(context, store),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Daypencil'),
              onTap: () => context.push('/about'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context, LocalStore store) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import progress'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Paste the export here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Import')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    try {
      final n = await store.importJson(text.trim());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $n item${n == 1 ? '' : 's'}')));
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: ${e.message}')));
    }
  }
}
