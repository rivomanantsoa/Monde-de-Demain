import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Native text reader for a downloaded pack. Works fully offline.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.item, this.sequence});
  final Readable item;

  /// For course lessons: the ordered list, to offer "next lesson".
  final List<Readable>? sequence;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final Future<Pack> _pack;
  final _scroll = ScrollController();
  late final AppState _app;
  bool _restored = false;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _pack = _app.readPack(widget.item);
    // Track the offset while scrolling: by the time dispose() runs the list
    // is already detached from the controller.
    _scroll.addListener(() {
      if (_scroll.hasClients) _offset = _scroll.offset;
    });
  }

  @override
  void dispose() {
    if (_restored) _app.saveReadingOffset(widget.item.key, _offset);
    _scroll.dispose();
    super.dispose();
  }

  void _restorePosition() {
    if (_restored) return;
    _restored = true;
    final target = _app.readingOffset(widget.item.key);
    _offset = target;
    if (target > 0) _jumpTowards(target, 10);
  }

  /// A lazy list only knows its extent for the items built so far, so a
  /// single jumpTo() is clamped short; step there over a few frames.
  void _jumpTowards(double target, int attemptsLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      _scroll.jumpTo(target.clamp(0, pos.maxScrollExtent));
      if (pos.pixels < target - 1 && attemptsLeft > 0) _jumpTowards(target, attemptsLeft - 1);
    });
  }

  Readable? get _next {
    final seq = widget.sequence;
    if (seq == null) return null;
    final i = seq.indexWhere((r) => r.key == widget.item.key);
    return (i >= 0 && i + 1 < seq.length) ? seq[i + 1] : null;
  }

  void _textSizeSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final app = AppScope.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.s.textSize, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Slider(
                        value: app.textScale,
                        min: 0.8,
                        max: 1.8,
                        divisions: 10,
                        activeColor: Brand.red,
                        label: '${(app.textScale * 100).round()}%',
                        onChanged: (v) => app.textScale = v,
                      ),
                    ),
                    const Text('A', style: TextStyle(fontSize: 26)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final next = _next;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: app.s.textSize,
            icon: const Icon(Icons.format_size),
            onPressed: _textSizeSheet,
          ),
        ],
      ),
      body: FutureBuilder<Pack>(
        future: _pack,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(icon: Icons.error_outline, message: '${snap.error}');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Brand.red));
          }
          final pack = snap.data!;
          _restorePosition();
          return Directionality(
            textDirection: app.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                itemCount: pack.blocks.length + 2,
                itemBuilder: (context, i) {
                  if (i == 0) return _Header(pack: pack, scale: app.textScale);
                  if (i == pack.blocks.length + 1) {
                    if (next == null) return const SizedBox(height: 24);
                    return Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: Text('${app.s.nextLesson} : ${next.title}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          if (!app.isDownloaded(next) && !await startDownload(context, next)) return;
                          nav.pushReplacement(MaterialPageRoute(
                            builder: (_) => ReaderScreen(item: next, sequence: widget.sequence),
                          ));
                        },
                      ),
                    );
                  }
                  return _BlockView(
                    block: pack.blocks[i - 1],
                    number: pack.listNumbers[i - 1],
                    scale: app.textScale,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pack, required this.scale});
  final Pack pack;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 40, height: 5, color: Brand.red),
          const SizedBox(height: 16),
          Text(
            pack.title,
            style: TextStyle(
              fontFamily: Brand.serif,
              fontSize: 28 * scale,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (pack.author.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(pack.author,
                style: TextStyle(fontSize: 14 * scale, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.scale, this.number = 0});
  final Block block;
  final double scale;

  /// Position in a numbered list (0 for anything else).
  final int number;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = TextStyle(
      fontFamily: Brand.serif,
      fontSize: 17.5 * scale,
      height: 1.6,
      color: cs.onSurface,
    );
    switch (block.type) {
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 10),
          child: Text(block.text,
              style: body.copyWith(fontSize: 23 * scale, height: 1.25, fontWeight: FontWeight.w800)),
        );
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(block.text,
              style: body.copyWith(
                fontFamily: null,
                fontSize: 18 * scale,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark ? Brand.redOnDark : Brand.redDark,
              )),
        );
      case 'q':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsetsDirectional.only(start: 16, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: Brand.red, width: 3)),
          ),
          child: Text.rich(_inline(block.text, body.copyWith(fontStyle: FontStyle.italic))),
        );
      case 'li':
      case 'ol':
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.type == 'ol')
                SizedBox(
                  width: 28 * scale,
                  child: Text('$number.',
                      style: body.copyWith(fontWeight: FontWeight.w700, color: Brand.red)),
                )
              else ...[
                Padding(
                  padding: EdgeInsets.only(top: 11 * scale),
                  child: Container(width: 6, height: 6, color: Brand.red),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text.rich(_inline(block.text, body))),
            ],
          ),
        );
      case 'img':
        return _LazyImage(url: block.text);
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(_inline(block.text, body)),
        );
    }
  }
}

/// Parses the tiny inline markup used in packs: <b>…</b> and <i>…</i>.
TextSpan _inline(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  var bold = false, italic = false;
  final re = RegExp(r'<(/?)([bi])>');
  var last = 0;
  void add(String t) {
    if (t.isEmpty) return;
    spans.add(TextSpan(
      text: t,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w700 : null,
        fontStyle: italic ? FontStyle.italic : null,
      ),
    ));
  }

  for (final m in re.allMatches(text)) {
    add(text.substring(last, m.start));
    final on = m.group(1)!.isEmpty;
    if (m.group(2) == 'b') {
      bold = on;
    } else {
      italic = on;
    }
    last = m.end;
  }
  add(text.substring(last));
  return TextSpan(style: base, children: spans);
}

/// In-text images are never downloaded automatically (data saver). The user
/// taps to load them when online; they are not stored on the device.
class _LazyImage extends StatefulWidget {
  const _LazyImage({required this.url});
  final String url;

  @override
  State<_LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<_LazyImage> {
  bool _load = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppScope.of(context).s;
    final placeholder = OutlinedButton.icon(
      icon: const Icon(Icons.image_outlined),
      label: Text(s.tapToLoadImage),
      onPressed: () => setState(() => _load = true),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _load
          ? Image.network(
              widget.url,
              loadingBuilder: (c, child, p) => p == null
                  ? child
                  : const SizedBox(
                      height: 120, child: Center(child: CircularProgressIndicator(color: Brand.red))),
              errorBuilder: (_, _, _) => Text(s.noConnection, style: TextStyle(color: cs.onSurfaceVariant)),
            )
          : Align(alignment: AlignmentDirectional.centerStart, child: placeholder),
    );
  }
}
