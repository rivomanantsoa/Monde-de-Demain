import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'language_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(s.language),
            subtitle: Text(app.language?.native ?? app.lang ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LanguageScreen())),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: Text(s.showCovers),
            subtitle: Text(s.showCoversHint),
            value: app.showCovers,
            onChanged: (v) => app.showCovers = v,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.contrast),
            title: Text(s.theme),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: Brand.red,
                  selectedForegroundColor: Brand.white,
                ),
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(s.themeSystem)),
                  ButtonSegment(value: ThemeMode.light, label: Text(s.themeLight)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(s.themeDark)),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (v) => app.themeMode = v.first,
              ),
            ),
          ),
          const Divider(),
          // Recomputed on every rebuild so it follows downloads/deletions.
          FutureBuilder<int>(
            future: app.storageBytes(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: Text(s.storageUsed),
              subtitle: Text(snap.hasData ? s.size(snap.data!) : '…'),
              trailing: TextButton(
                style: TextButton.styleFrom(foregroundColor: Brand.red),
                onPressed: app.downloads.isEmpty ? null : () => _confirmDeleteAll(context),
                child: Text(s.deleteAll),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(s.dataNote, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final app = AppScope.read(context);
    final s = app.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.confirmDeleteAll),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.delete)),
        ],
      ),
    );
    if (ok == true) await app.deleteAll();
  }
}
