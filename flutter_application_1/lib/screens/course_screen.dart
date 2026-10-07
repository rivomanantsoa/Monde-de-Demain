import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CourseScreen extends StatelessWidget {
  const CourseScreen({super.key, required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final cs = Theme.of(context).colorScheme;
    final course = app.catalog?.courses.where((c) => c.id == courseId).firstOrNull;
    if (course == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.school, message: s.emptyContent));
    }
    final missing = course.lessons.where((l) => !app.isDownloaded(l) || app.hasUpdate(l)).toList();
    final missingSize = missing.fold<int>(0, (a, l) => a + l.size);

    return Scaffold(
      appBar: AppBar(title: Text(course.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (course.summary.isNotEmpty)
                  Text(course.summary, style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
                const SizedBox(height: 16),
                if (missing.isNotEmpty)
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text('${s.downloadAll} (${s.size(missingSize)})'),
                    onPressed: () async {
                      for (final l in missing) {
                        if (!context.mounted) return;
                        if (!await startDownload(context, l)) return;
                      }
                    },
                  ),
              ],
            ),
          ),
          for (var i = 0; i < course.lessons.length; i++) ...[
            if (i > 0) const Divider(indent: 72),
            ListTile(
              key: ValueKey(course.lessons[i].key),
              minVerticalPadding: 12,
              leading: CircleAvatar(
                backgroundColor: app.isDownloaded(course.lessons[i]) ? Brand.red : cs.surfaceContainerHighest,
                foregroundColor: app.isDownloaded(course.lessons[i]) ? Brand.white : cs.onSurface,
                child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              title: Text(course.lessons[i].title,
                  style: const TextStyle(fontFamily: Brand.serif, fontWeight: FontWeight.w600)),
              subtitle: Row(children: [
                Text(s.size(course.lessons[i].size)),
                if (app.bookmarks.has(course.lessons[i].key)) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.bookmark, size: 16, color: Brand.red, semanticLabel: s.bookmark),
                ],
              ]),
              trailing: DownloadButton(item: course.lessons[i]),
              onTap: () => openReadable(context, course.lessons[i], sequence: course.lessons),
            ),
          ],
        ],
      ),
    );
  }
}
