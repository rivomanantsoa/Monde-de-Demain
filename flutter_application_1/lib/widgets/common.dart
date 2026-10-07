import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/reader_screen.dart';
import '../theme.dart';

/// Brochure cover: the real thumbnail when covers are enabled (data saver
/// off), otherwise a typographic red/black cover drawn locally (0 bytes).
class Cover extends StatelessWidget {
  const Cover({super.key, required this.item, this.width = 64, this.aspect = 1.5});
  final Readable item;
  final double width;

  /// Height / width (brochures 1.5, magazines ~1.34).
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final h = width * aspect;
    final placeholder = _TypographicCover(title: item.title, width: width, height: h);
    if (!item.hasCover) return placeholder;
    return FutureBuilder<File?>(
      // showCovers is read so the cover appears as soon as it is switched on.
      key: ValueKey('${item.coverPath}-${app.showCovers}'),
      future: app.cover(item),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.file(
            f,
            width: width,
            height: h,
            fit: BoxFit.cover,
            cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
      },
    );
  }
}

class _TypographicCover extends StatelessWidget {
  const _TypographicCover({required this.title, required this.width, required this.height});
  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // On a black background a black cover would vanish: lift it slightly.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF262626) : Brand.black,
        borderRadius: BorderRadius.circular(3),
        border: dark ? Border.all(color: const Color(0xFF3A3A3A)) : null,
      ),
      padding: EdgeInsets.all(width * 0.09),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: width * 0.3, height: 3, color: Brand.red),
          SizedBox(height: width * 0.08),
          Expanded(
            child: Text(
              title,
              maxLines: 5,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontFamily: Brand.serif,
                color: Brand.white,
                // small enough that common long words fit on one line
                fontSize: width * 0.115,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Download / progress / downloaded indicator for one readable item.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.item, this.compact = true});
  final Readable item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    if (app.inProgress.containsKey(item.key)) {
      final p = app.inProgress[item.key];
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(value: p, strokeWidth: 3, color: Brand.red),
          ),
        ),
      );
    }
    if (app.hasUpdate(item)) {
      return IconButton(
        tooltip: '${s.update} (${s.size(item.size)})',
        icon: const Icon(Icons.update, color: Brand.red),
        onPressed: () => startDownload(context, item),
      );
    }
    if (app.isDownloaded(item)) {
      return Tooltip(
        message: s.downloaded,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.offline_pin, color: Brand.red),
        ),
      );
    }
    return IconButton(
      tooltip: '${s.download} (${s.size(item.size)})',
      icon: const Icon(Icons.download_outlined),
      onPressed: () => startDownload(context, item),
    );
  }
}

Future<bool> startDownload(BuildContext context, Readable item) async {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await app.download(item);
  if (!ok) {
    messenger.showSnackBar(SnackBar(
      persist: false,
      duration: const Duration(seconds: 6),
      content: Text(app.s.noConnection),
      action: SnackBarAction(label: app.s.retry, onPressed: () => app.download(item)),
    ));
  }
  return ok;
}

/// Opens an item: reads it if downloaded, otherwise downloads it first.
Future<void> openReadable(BuildContext context, Readable item, {List<Readable>? sequence}) async {
  final app = AppScope.read(context);
  final nav = Navigator.of(context);
  if (!app.isDownloaded(item)) {
    final ok = await startDownload(context, item);
    if (!ok) return;
  }
  nav.push(MaterialPageRoute(builder: (_) => ReaderScreen(item: item, sequence: sequence)));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, height: 1.5),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Thin strip shown when a list comes from the local copy (offline).
/// Defaults to the main catalog; sections pass their own state.
class OfflineStrip extends StatelessWidget {
  const OfflineStrip({super.key, this.fromCache, this.onRefresh});
  final bool? fromCache;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final offline = fromCache ?? (app.catalogFromCache && app.catalog != null);
    if (!offline) return const SizedBox.shrink();
    return Material(
      color: Brand.black,
      child: InkWell(
        onTap: onRefresh ?? app.refreshCatalog,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, size: 16, color: Brand.redOnDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(app.s.offlineNote, style: const TextStyle(color: Brand.white, fontSize: 13)),
              ),
              const Icon(Icons.refresh, size: 18, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
