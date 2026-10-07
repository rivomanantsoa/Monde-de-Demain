import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'course_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // One conditional request per launch; ~0 bytes when nothing changed.
    WidgetsBinding.instance.addPostFrameCallback((_) => AppScope.read(context).refreshCatalog());
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).s;
    const pages = [_BrochuresTab(), _CoursesTab(), _LibraryTab(), SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: s.brochures),
          NavigationDestination(icon: const Icon(Icons.school_outlined), selectedIcon: const Icon(Icons.school), label: s.courses),
          NavigationDestination(icon: const Icon(Icons.offline_pin_outlined), selectedIcon: const Icon(Icons.offline_pin), label: s.library),
          NavigationDestination(icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune), label: s.settings),
        ],
      ),
    );
  }
}

/// Shared handling of loading / offline / empty for catalog-based tabs.
Widget _catalogBody(BuildContext context, Widget Function(Catalog c) builder) {
  final app = AppScope.of(context);
  final c = app.catalog;
  if (c == null) {
    if (app.catalogLoading) return const Center(child: CircularProgressIndicator(color: Brand.red));
    return EmptyState(
      icon: Icons.cloud_off,
      message: app.s.noConnection,
      action: FilledButton(onPressed: app.refreshCatalog, child: Text(app.s.retry)),
    );
  }
  return Column(
    children: [
      const OfflineStrip(),
      Expanded(
        child: RefreshIndicator(
          color: Brand.red,
          onRefresh: app.refreshCatalog,
          child: builder(c),
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------------ brochures
class _BrochuresTab extends StatefulWidget {
  const _BrochuresTab();

  @override
  State<_BrochuresTab> createState() => _BrochuresTabState();
}

class _BrochuresTabState extends State<_BrochuresTab> {
  String _query = '';
  bool _searching = false;

  String _norm(String v) => v.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Brand.white),
                cursorColor: Brand.red,
                decoration: InputDecoration(
                  hintText: s.search,
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text(kAppName),
        actions: [
          IconButton(
            tooltip: s.search,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
        ],
      ),
      body: _catalogBody(context, (c) {
        final q = _norm(_query.trim());
        final items = q.isEmpty
            ? c.brochures
            : c.brochures
                .where((b) => _norm(b.title).contains(q) || _norm(b.author).contains(q))
                .toList();
        if (c.brochures.isEmpty) {
          return ListView(children: [
            SizedBox(height: 400, child: EmptyState(icon: Icons.translate, message: s.emptyContent)),
          ]);
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(indent: 96),
          itemBuilder: (context, i) => _BrochureTile(key: ValueKey(items[i].key), item: items[i]),
        );
      }),
    );
  }
}

class _BrochureTile extends StatelessWidget {
  const _BrochureTile({super.key, required this.item});
  final Readable item;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => openReadable(context, item),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Cover(item: item),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: Brand.serif,
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.author, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    app.isDownloaded(item) ? app.s.downloaded : app.s.size(item.size),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: app.isDownloaded(item) ? Brand.red : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            DownloadButton(item: item),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ courses
class _CoursesTab extends StatelessWidget {
  const _CoursesTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s.courses)),
      body: _catalogBody(context, (c) {
        if (c.courses.isEmpty) {
          return ListView(children: [
            SizedBox(height: 400, child: EmptyState(icon: Icons.school_outlined, message: s.emptyContent)),
          ]);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: c.courses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final course = c.courses[i];
            final done = course.lessons.where(app.isDownloaded).length;
            return Material(
              key: ValueKey(course.id),
              color: cs.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: cs.outline),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CourseScreen(courseId: course.id)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 32, height: 4, color: Brand.red),
                      const SizedBox(height: 12),
                      Text(course.title,
                          style: const TextStyle(
                              fontFamily: Brand.serif, fontSize: 20, fontWeight: FontWeight.w700)),
                      if (course.summary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(course.summary,
                            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '${course.lessons.length} ${s.lessons} · ${s.size(course.totalSize)}'
                        '${done > 0 ? ' · $done/${course.lessons.length} ✓' : ''}',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ------------------------------------------------------------------ library
class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final cs = Theme.of(context).colorScheme;

    // Downloaded items of the current language, resolved against the catalog
    // when possible (works offline from the manifest otherwise).
    final prefix = '${app.lang}/';
    final known = <String, Readable>{
      for (final b in app.catalog?.brochures ?? const <Readable>[]) b.key: b,
      for (final c in app.catalog?.courses ?? const <Course>[])
        for (final l in c.lessons) l.key: l,
    };
    final entries = app.downloads.entries.where((e) => e.key.startsWith(prefix)).toList();
    final items = [
      for (final e in entries)
        known[e.key] ??
            Readable(
              key: e.key,
              path: e.value['p'] as String,
              title: e.value['t'] as String? ?? e.key,
              size: e.value['sz'] as int? ?? 0,
              version: e.value['v'] as String? ?? '',
            ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(s.library)),
      body: items.isEmpty
          ? EmptyState(icon: Icons.offline_pin_outlined, message: s.emptyLibrary)
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final it = items[i];
                final bytes = app.downloads[it.key]?['sz'] as int? ?? 0;
                return ListTile(
                  key: ValueKey(it.key),
                  minVerticalPadding: 12,
                  leading: Icon(it.key.contains('/k/') ? Icons.school : Icons.menu_book,
                      color: Brand.red),
                  title: Text(it.title,
                      style: const TextStyle(fontFamily: Brand.serif, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    app.hasUpdate(it) ? s.updateAvailable : s.size(bytes),
                    style: TextStyle(color: app.hasUpdate(it) ? Brand.red : cs.onSurfaceVariant),
                  ),
                  onTap: () => openReadable(context, it),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (app.bookmarks.has(it.key))
                        Tooltip(
                          message: s.bookmark,
                          child: const Icon(Icons.bookmark, color: Brand.red, size: 20),
                        ),
                      if (app.hasUpdate(it)) DownloadButton(item: it),
                      IconButton(
                        tooltip: s.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => app.delete(it.key),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
