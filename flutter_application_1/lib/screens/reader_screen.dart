import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../bookmarks/bookmark_widgets.dart';
import '../bookmarks/bookmarks.dart';
import '../models.dart';
import '../reader/book_view.dart';
import '../reader/paginator.dart';
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
  bool? _wasPaged;
  final _paged = GlobalKey<_PagedReaderState>();
  final _blockKeys = <int, GlobalKey>{}; // scroll mode: built paragraphs
  int _blockCount = 0;

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

  Widget _nextButton(Readable next) {
    final app = AppScope.of(context);
    return FilledButton.icon(
      icon: const Icon(Icons.arrow_forward),
      label: Text('${app.s.nextLesson} : ${next.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: () async {
        final nav = Navigator.of(context);
        if (!app.isDownloaded(next) && !await startDownload(context, next)) return;
        nav.pushReplacement(MaterialPageRoute(
          builder: (_) => ReaderScreen(item: next, sequence: widget.sequence),
        ));
      },
    );
  }

  // ---------------------------------------------------------------- bookmark
  ReadingMark? get _mark => _app.bookmarks.get(widget.item.key);

  void _placeMark(int block, int char) {
    final previous = _mark;
    _app.bookmarks.set(widget.item.key, block, char);
    HapticFeedback.mediumImpact();
    final s = _app.s;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        // A SnackBar with an action persists by default: dismiss it anyway.
        persist: false,
        duration: const Duration(seconds: 4),
        content: Row(children: [
          const BookmarkRibbon(width: 10, height: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(s.bookmarkPlaced)),
        ]),
        action: SnackBarAction(
          label: s.undo,
          onPressed: () => _app.bookmarks.restore(widget.item.key, previous),
        ),
      ));
  }

  /// "Mark here": the current page (page mode) or the first paragraph
  /// visible on screen (scroll mode).
  void _placeHere() {
    if (_app.pagedReading) {
      final a = _paged.currentState?.currentAnchor;
      if (a != null) _placeMark(a.$1, a.$2);
      return;
    }
    final viewport = _scroll.position.context.notificationContext?.findRenderObject() as RenderBox?;
    final top = viewport?.localToGlobal(Offset.zero).dy ?? 0;
    final bottom = top + (viewport?.size.height ?? 0);
    final built = _blockKeys.keys.toList()..sort();
    int? containing;
    for (final i in built) {
      final box = _blockKeys[i]!.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= top) continue;
      // Prefer the first paragraph whose start is on screen, so the marker
      // is visible right away; else the one cut at the top.
      if (y >= top - 4 && y < bottom - 40) {
        _placeMark(i, 0);
        return;
      }
      containing ??= i;
    }
    _placeMark(containing ?? -1, 0);
  }

  void _goToMark() {
    final m = _mark;
    if (m == null) return;
    if (_app.pagedReading) {
      _paged.currentState?.goToAnchor(m.anchor);
    } else {
      _scrollToBlock(m.block, 8);
    }
  }

  /// Scroll mode: the paragraph may not be built yet (lazy list), so jump to
  /// an estimated offset first, then align precisely once it exists.
  void _scrollToBlock(int block, int attemptsLeft) {
    final ctx = _blockKeys[block]?.currentContext;
    if (ctx != null) {
      // Align the paragraph's top with the top of the screen (alignment 0:
      // a non-zero alignment pushes paragraphs taller than the screen above
      // it), then leave a small margin. Paragraphs above get their real
      // height while scrolling, so align once more when the animation ends.
      void settle() {
        final again = _blockKeys[block]?.currentContext;
        if (!mounted || again == null || !again.mounted) return;
        Scrollable.ensureVisible(again);
        final pos = _scroll.position;
        _scroll.jumpTo((pos.pixels - 16).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      }

      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300)).then((_) => settle());
      return;
    }
    if (block < 0) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      return;
    }
    if (attemptsLeft == 0 || !_scroll.hasClients) return;
    final pos = _scroll.position;
    _scroll.jumpTo(pos.maxScrollExtent * (block + 1) / (_blockCount + 2));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBlock(block, attemptsLeft - 1));
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
          BookmarkButton(
            mark: app.bookmarks.get(widget.item.key),
            labels: BookmarkLabels(
              bookmark: app.s.bookmark,
              placeHere: app.s.bookmarkHere,
              goTo: app.s.bookmarkGoTo,
              remove: app.s.bookmarkRemove,
              hint: app.s.bookmarkHint,
            ),
            onPlaceHere: _placeHere,
            onGoTo: _goToMark,
            onRemove: () => app.bookmarks.remove(widget.item.key),
          ),
          IconButton(
            tooltip: '${app.s.readingMode} : ${app.pagedReading ? app.s.modeScroll : app.s.modePages}',
            icon: Icon(app.pagedReading ? Icons.swap_vert : Icons.auto_stories_outlined),
            onPressed: () => app.pagedReading = !app.pagedReading,
          ),
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
          _blockCount = pack.blocks.length;
          final mark = app.bookmarks.get(widget.item.key);
          if (_wasPaged != app.pagedReading) {
            // Coming back to scroll mode: restore the scroll offset again.
            if (!app.pagedReading) {
              if (_restored) _app.saveReadingOffset(widget.item.key, _offset);
              _restored = false;
            }
            _wasPaged = app.pagedReading;
          }
          if (app.pagedReading) {
            return Directionality(
              textDirection: app.rtl ? TextDirection.rtl : TextDirection.ltr,
              child: _PagedReader(
                key: _paged,
                pack: pack,
                item: widget.item,
                mark: mark,
                onMark: _placeMark,
                nextButton: next == null ? null : _nextButton(next),
              ),
            );
          }
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
                  if (i == 0) {
                    return MarkableParagraph(
                      key: _blockKeys.putIfAbsent(-1, GlobalKey.new),
                      marked: mark?.block == -1,
                      onMark: () => _placeMark(-1, 0),
                      markerTop: 30,
                      child: _Header(pack: pack, scale: app.textScale),
                    );
                  }
                  if (i == pack.blocks.length + 1) {
                    if (next == null) return const SizedBox(height: 24);
                    return Padding(padding: const EdgeInsets.only(top: 32), child: _nextButton(next));
                  }
                  final b = i - 1;
                  final type = pack.blocks[b].type;
                  return MarkableParagraph(
                    key: _blockKeys.putIfAbsent(b, GlobalKey.new),
                    marked: mark?.block == b,
                    onMark: () => _placeMark(b, 0),
                    // align with the first line (after the block's top padding)
                    markerTop: switch (type) { 'h2' => 32, 'h3' => 22, 'q' => 16, _ => 6 },
                    child: _BlockView(block: pack.blocks[b], number: pack.listNumbers[b], scale: app.textScale),
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
  const _LazyImage({required this.url, this.height});
  final String url;

  /// Fixed box height (page mode); null = natural height (scroll mode).
  final double? height;

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
    if (widget.height != null) {
      return SizedBox(
        height: widget.height,
        child: _load
            ? Image.network(
                widget.url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Center(child: Text(s.noConnection, style: TextStyle(color: cs.onSurfaceVariant))),
              )
            : Center(child: placeholder),
      );
    }
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

// ------------------------------------------------------------------ page mode

/// Book mode: the pack is cut into pages that fit the screen, turned with a
/// page-fold animation. Re-paginates when the text size or screen changes,
/// keeping the reader on the same passage.
class _PagedReader extends StatefulWidget {
  const _PagedReader({
    super.key,
    required this.pack,
    required this.item,
    required this.mark,
    required this.onMark,
    this.nextButton,
  });
  final Pack pack;
  final Readable item;
  final ReadingMark? mark;
  final void Function(int block, int char) onMark;
  final Widget? nextButton;

  @override
  State<_PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<_PagedReader> {
  static const _pad = EdgeInsets.fromLTRB(22, 24, 22, 0);
  static const _footer = 40.0;

  late final AppState _app = AppScope.read(context);
  late (int, int) _anchor = _app.readingAnchor(widget.item.key);
  String? _signature;
  List<BookPage> _pages = const [];
  int _initial = 0;
  int _current = 0;
  int _jumps = 0; // bumped to rebuild the book at a new page

  (int, int) get currentAnchor => _pages[_current].anchor;

  void goToAnchor((int, int) a) {
    final i = pageForAnchor(_pages, a);
    if (i == _current) return;
    setState(() {
      _jumps++;
      _initial = i;
    });
    _onPage(i);
  }

  /// Index of the item on [page] holding the mark, or -1.
  int _markedItem(BookPage page) {
    final m = widget.mark;
    if (m == null) return -1;
    var found = -1;
    for (var k = 0; k < page.items.length; k++) {
      final it = page.items[k];
      if (it.blockIndex == m.block && it.start <= m.char) found = k;
    }
    return found;
  }

  void _onPage(int i) {
    setState(() => _current = i);
    _anchor = _pages[i].anchor;
    _app.saveReadingAnchor(widget.item.key, _anchor);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final st = ReaderStyles(context, app.textScale);
    final dir = Directionality.of(context);

    return LayoutBuilder(builder: (context, c) {
      final content = Size(c.maxWidth - _pad.horizontal, c.maxHeight - _pad.top - _footer);
      final sig = '${content.width.round()}x${content.height.round()}|${st.scale}|${st.textScaler}|$dir';
      if (sig != _signature) {
        _signature = sig;
        _pages = paginate(widget.pack, st, content, dir);
        _initial = pageForAnchor(_pages, _anchor);
        _current = _initial;
      }
      final last = _current == _pages.length - 1;
      return Stack(
        children: [
          Positioned.fill(
            child: BookView(
              key: ValueKey('$sig#$_jumps'),
              pageCount: _pages.length,
              initialPage: _initial,
              onPageChanged: _onPage,
              rtl: app.rtl,
              paperColor: cs.surface,
              backColor: dark ? const Color(0xFF3A3A3A) : const Color(0xFFEFEBE4),
              pageBuilder: (context, i) => _PageView(
                page: _pages[i],
                markedItem: widget.mark != null && pageForAnchor(_pages, widget.mark!.anchor) == i
                    ? _markedItem(_pages[i])
                    : -1,
                onMark: widget.onMark,
                styles: st,
                padding: _pad,
                contentHeight: content.height,
                footer: _footer,
                label: '${i + 1} / ${_pages.length}',
              ),
            ),
          ),
          if (last && widget.nextButton != null)
            Positioned(left: 22, right: 22, bottom: _footer + 8, child: widget.nextButton!),
        ],
      );
    });
  }
}

class _PageView extends StatelessWidget {
  const _PageView({
    required this.page,
    required this.markedItem,
    required this.onMark,
    required this.styles,
    required this.padding,
    required this.contentHeight,
    required this.footer,
    required this.label,
  });

  final BookPage page;

  /// Index in page.items of the marked paragraph; -1 when the mark is elsewhere.
  final int markedItem;
  final void Function(int block, int char) onMark;
  final ReaderStyles styles;
  final EdgeInsets padding;
  final double contentHeight;
  final double footer;
  final String label;

  Widget _text(PageItem it) => RichText(
        text: spanOf(it.runs, styles.styleFor(it.type)),
        textScaler: styles.textScaler,
      );

  Widget _item(PageItem it, bool marked) {
    final st = styles;
    final Widget body = switch (it.type) {
      'title' => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 40, height: 5, color: Brand.red),
            const SizedBox(height: 16),
            _text(it),
          ],
        ),
      'q' => Container(
          padding: const EdgeInsetsDirectional.only(start: 16),
          decoration: const BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: Brand.red, width: 3)),
          ),
          child: _text(it),
        ),
      'li' => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 4),
            if (it.marker)
              Padding(
                padding: EdgeInsets.only(top: 11 * st.scale),
                child: Container(width: 6, height: 6, color: Brand.red),
              )
            else
              const SizedBox(width: 6),
            const SizedBox(width: 12),
            Expanded(child: _text(it)),
          ],
        ),
      'ol' => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 4),
            SizedBox(
              width: 28 * st.scale,
              child: it.marker
                  ? RichText(text: TextSpan(text: '${it.number}.', style: st.olNumber), textScaler: st.textScaler)
                  : null,
            ),
            Expanded(child: _text(it)),
          ],
        ),
      'img' => _LazyImage(url: it.url!, height: ReaderStyles.imageHeight),
      _ => _text(it),
    };
    // The title's top gap holds its red bar, drawn inside the item.
    final top = it.type == 'title' ? 0.0 : it.gapTop;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: it.gapBottom),
      child: MarkableParagraph(
        marked: marked,
        onMark: () => onMark(it.blockIndex, it.start),
        markerTop: it.type == 'title' ? 25 : 4,
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sheet = Padding(
      padding: padding,
      child: Column(
        children: [
          SizedBox(
            height: contentHeight,
            child: ClipRect(
              clipper: const _ContentClipper(),
              // The last item's bottom gap may exceed the page: let it overflow
              // invisibly instead of throwing a layout error.
              child: OverflowBox(
                alignment: AlignmentDirectional.topStart,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var k = 0; k < page.items.length; k++) _item(page.items[k], k == markedItem),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: footer,
            child: Center(
              child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
    if (markedItem < 0) return sheet;
    // The marked page carries a ribbon hanging from its top edge.
    return Stack(
      children: [
        sheet,
        const PositionedDirectional(top: 0, end: 4, child: BookmarkRibbon(width: 14, height: 30)),
      ],
    );
  }
}

/// Clips overflow at the bottom of the page but leaves the side margins
/// visible (for the paragraph bookmark marker).
class _ContentClipper extends CustomClipper<Rect> {
  const _ContentClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-30, -30, size.width + 30, size.height);

  @override
  bool shouldReclip(_ContentClipper old) => false;
}
