import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'course_screen.dart';
import 'settings_screen.dart';

/// Bottom navigation: Read (the site's "LIRE" menu) · Offline · Settings.
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
    const pages = [_ReadScreen(), _LibraryTab(), SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: s.readTab),
          NavigationDestination(icon: const Icon(Icons.offline_pin_outlined), selectedIcon: const Icon(Icons.offline_pin), label: s.library),
          NavigationDestination(icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune), label: s.settings),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ read
/// Same sections, same order as the website's "LIRE" menu:
/// Cours de Bible · Brochures · Commentaire · Revue.
class _ReadScreen extends StatefulWidget {
  const _ReadScreen();

  @override
  State<_ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<_ReadScreen> with SingleTickerProviderStateMixin {
  late final AppState _app = AppScope.read(context);
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: _app.readTab);
  String _query = '';
  bool _searching = false;
  String? _lang;

  /// Tab index -> separate list file fetched on first visit.
  static const _sectionOfTab = {2: 'commentaires', 3: 'revues'};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      _app.readTab = _tabs.index;
      _ensureSection(_tabs.index);
    });
  }

  void _ensureSection(int tab) {
    final name = _sectionOfTab[tab];
    if (name != null && !_app.sections.containsKey(name)) _app.loadSection(name);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    // A new language clears the sections: reload the visible one (once).
    if (app.lang != _lang) {
      _lang = app.lang;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSection(_tabs.index));
    }
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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // Tight padding so the last tab peeks in on small screens.
          labelPadding: const EdgeInsets.symmetric(horizontal: 13),
          indicatorColor: Brand.red,
          indicatorWeight: 3,
          labelColor: Brand.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: s.bibleCourse),
            Tab(text: s.brochures),
            Tab(text: s.commentaries),
            Tab(text: s.magazines),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _CoursesBody(query: _query),
          _BrochuresBody(query: _query),
          _SectionBody(name: 'commentaires', query: _query, tile: (r) => _CommentTile(key: ValueKey(r.key), item: r)),
          _SectionBody(name: 'revues', query: _query, grouped: true, tile: (r) => _IssueTile(key: ValueKey(r.key), item: r)),
        ],
      ),
    );
  }
}

bool _matches(Readable r, String q) {
  if (q.isEmpty) return true;
  bool has(String v) => v.toLowerCase().contains(q);
  return has(r.title) || has(r.author) || r.articles.any(has);
}

Widget _emptyList(IconData icon, String message) => ListView(children: [
      SizedBox(height: 400, child: EmptyState(icon: icon, message: message)),
    ]);

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
        child: RefreshIndicator(color: Brand.red, onRefresh: app.refreshCatalog, child: builder(c)),
      ),
    ],
  );
}

/// Status line under an item: "Available offline" or its size.
class _Status extends StatelessWidget {
  const _Status({required this.item, this.prefix = ''});
  final Readable item;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final done = app.isDownloaded(item);
    return Row(children: [
      Flexible(
        child: Text(
          '$prefix${done ? app.s.downloaded : app.s.size(item.size)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: done ? Brand.red : cs.onSurfaceVariant),
        ),
      ),
      if (app.bookmarks.has(item.key)) ...[
        const SizedBox(width: 6),
        Icon(Icons.bookmark, size: 14, color: Brand.red, semanticLabel: app.s.bookmark),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ brochures
class _BrochuresBody extends StatelessWidget {
  const _BrochuresBody({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).s;
    return _catalogBody(context, (c) {
      if (c.brochures.isEmpty) return _emptyList(Icons.translate, s.emptyContent);
      final q = query.trim().toLowerCase();
      final items = c.brochures.where((b) => _matches(b, q)).toList();
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(indent: 96),
        itemBuilder: (context, i) => _BrochureTile(key: ValueKey(items[i].key), item: items[i]),
      );
    });
  }
}

class _BrochureTile extends StatelessWidget {
  const _BrochureTile({super.key, required this.item});
  final Readable item;

  @override
  Widget build(BuildContext context) {
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
                  Text(item.title,
                      style: const TextStyle(fontFamily: Brand.serif, fontSize: 17, height: 1.25, fontWeight: FontWeight.w700)),
                  if (item.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.author, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 6),
                  _Status(item: item),
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
class _CoursesBody extends StatelessWidget {
  const _CoursesBody({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final cs = Theme.of(context).colorScheme;
    return _catalogBody(context, (c) {
      if (c.courses.isEmpty) return _emptyList(Icons.school_outlined, s.emptyContent);
      final q = query.trim().toLowerCase();
      final courses = c.courses
          .where((k) => q.isEmpty || k.title.toLowerCase().contains(q) || k.lessons.any((l) => _matches(l, q)))
          .toList();
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: courses.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final course = courses[i];
          final done = course.lessons.where(app.isDownloaded).length;
          return Material(
            key: ValueKey(course.id),
            color: cs.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: cs.outline)),
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
                        style: const TextStyle(fontFamily: Brand.serif, fontSize: 20, fontWeight: FontWeight.w700)),
                    if (course.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(course.summary, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '${course.lessons.length} ${s.lessons} · ${s.size(course.totalSize)}'
                      '${done > 0 ? ' · $done/${course.lessons.length} ✓' : ''}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

// ------------------------------------------------------------------ sections
/// A tab backed by its own list file (commentaires, revues).
class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.name, required this.query, required this.tile, this.grouped = false});
  final String name;
  final String query;
  final Widget Function(Readable) tile;

  /// Group by year with headers (magazine issues).
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final all = app.sections[name];
    if (all == null) {
      if (app.sectionLoading.contains(name) || app.catalog == null) {
        return const Center(child: CircularProgressIndicator(color: Brand.red));
      }
      return EmptyState(
        icon: Icons.cloud_off,
        message: s.noConnection,
        action: FilledButton(onPressed: () => app.loadSection(name), child: Text(s.retry)),
      );
    }
    final q = query.trim().toLowerCase();
    final items = all.where((r) => _matches(r, q)).toList();

    // Flat list of rows: an int is a year header, a Readable an item.
    final rows = <Object>[];
    for (final r in items) {
      if (grouped && r.year != null && (rows.isEmpty || (rows.last is Readable && (rows.last as Readable).year != r.year))) {
        rows.add(r.year!);
      }
      rows.add(r);
    }

    return Column(
      children: [
        OfflineStrip(fromCache: app.sectionFromCache.contains(name), onRefresh: () => app.loadSection(name)),
        Expanded(
          child: RefreshIndicator(
            color: Brand.red,
            onRefresh: () => app.loadSection(name),
            child: all.isEmpty
                ? _emptyList(Icons.translate, s.emptyContent)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      if (row is int) return _YearHeader(year: row);
                      return tile(row as Readable);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _YearHeader extends StatelessWidget {
  const _YearHeader({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(children: [
        Container(width: 4, height: 22, color: Brand.red),
        const SizedBox(width: 10),
        Text('$year', style: const TextStyle(fontFamily: Brand.serif, fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({super.key, required this.item});
  final Readable item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = [item.author, item.date].where((v) => v.isNotEmpty).join(' · ');
    return Column(
      children: [
        InkWell(
          onTap: () => openReadable(context, item),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(fontFamily: Brand.serif, fontSize: 17, height: 1.25, fontWeight: FontWeight.w700)),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(meta, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ],
                      if (item.summary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(item.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 6),
                      _Status(item: item),
                    ],
                  ),
                ),
                DownloadButton(item: item),
              ],
            ),
          ),
        ),
        const Divider(indent: 16),
      ],
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({super.key, required this.item});
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
            Cover(item: item, aspect: 1.34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(fontFamily: Brand.serif, fontSize: 17, height: 1.25, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  // The issue's contents: first article titles.
                  Text(
                    item.articles.take(3).join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  _Status(item: item, prefix: '${item.articles.length} ${app.s.articles} · '),
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

// ------------------------------------------------------------------ library
class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  static IconData _icon(String key) {
    if (key.contains('/k/')) return Icons.school;
    if (key.contains('/m/')) return Icons.article_outlined;
    if (key.contains('/r/')) return Icons.newspaper;
    return Icons.menu_book;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final cs = Theme.of(context).colorScheme;

    // Downloaded items of the current language, resolved against the lists
    // when possible (works offline from the manifest otherwise).
    final prefix = '${app.lang}/';
    final known = app.knownItems;
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
                  leading: Icon(_icon(it.key), color: Brand.red),
                  title: Text(it.title, style: const TextStyle(fontFamily: Brand.serif, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    app.hasUpdate(it) ? s.updateAvailable : s.size(bytes),
                    style: TextStyle(color: app.hasUpdate(it) ? Brand.red : cs.onSurfaceVariant),
                  ),
                  onTap: () => openReadable(context, it),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (app.bookmarks.has(it.key))
                        Tooltip(message: s.bookmark, child: const Icon(Icons.bookmark, color: Brand.red, size: 20)),
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
