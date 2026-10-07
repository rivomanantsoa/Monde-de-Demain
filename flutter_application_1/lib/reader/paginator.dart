import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// A piece of inline text with its style flags (from the pack's <b>/<i>).
class Run {
  const Run(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold;
  final bool italic;
}

List<Run> parseRuns(String text) {
  final runs = <Run>[];
  var bold = false, italic = false, last = 0;
  void add(String t) {
    if (t.isNotEmpty) runs.add(Run(t, bold: bold, italic: italic));
  }

  for (final m in RegExp(r'<(/?)([bi])>').allMatches(text)) {
    add(text.substring(last, m.start));
    final on = m.group(1)!.isEmpty;
    m.group(2) == 'b' ? bold = on : italic = on;
    last = m.end;
  }
  add(text.substring(last));
  return runs;
}

/// Runs restricted to the plain-text range [start, end).
List<Run> sliceRuns(List<Run> runs, int start, [int? end]) {
  final out = <Run>[];
  var pos = 0;
  for (final r in runs) {
    final s = pos, e = pos + r.text.length;
    pos = e;
    final a = start.clamp(s, e), b = (end ?? e).clamp(s, e);
    if (b > a) out.add(Run(r.text.substring(a - s, b - s), bold: r.bold, italic: r.italic));
  }
  return out;
}

int runsLength(List<Run> runs) => runs.fold(0, (a, r) => a + r.text.length);

TextSpan spanOf(List<Run> runs, TextStyle style) => TextSpan(
      style: style,
      children: [
        for (final r in runs)
          TextSpan(
            text: r.text,
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.w700 : null,
              fontStyle: r.italic ? FontStyle.italic : null,
            ),
          ),
      ],
    );

/// Every size and style used by the reader, shared by the scroll view, the
/// paginator (measuring) and the page renderer (drawing), so that what is
/// measured is exactly what is drawn.
class ReaderStyles {
  ReaderStyles(BuildContext context, this.scale)
      : textScaler = MediaQuery.textScalerOf(context),
        dark = Theme.of(context).brightness == Brightness.dark,
        ink = Theme.of(context).colorScheme.onSurface,
        muted = Theme.of(context).colorScheme.onSurfaceVariant;

  final double scale;
  final TextScaler textScaler;
  final bool dark;
  final Color ink;
  final Color muted;

  TextStyle get body => TextStyle(
        fontFamily: Brand.serif,
        fontSize: 17.5 * scale,
        height: 1.6,
        color: ink,
      );
  TextStyle get h2 => body.copyWith(fontSize: 23 * scale, height: 1.25, fontWeight: FontWeight.w800);
  TextStyle get h3 => TextStyle(
        fontSize: 18 * scale,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: dark ? Brand.redOnDark : Brand.redDark,
      );
  TextStyle get quote => body.copyWith(fontStyle: FontStyle.italic);
  TextStyle get title => body.copyWith(fontSize: 28 * scale, height: 1.2, fontWeight: FontWeight.w800);
  TextStyle get author =>
      TextStyle(fontSize: 14 * scale, height: 1.4, color: muted, fontWeight: FontWeight.w600);
  TextStyle get olNumber => body.copyWith(fontWeight: FontWeight.w700, color: Brand.red);

  TextStyle styleFor(String type) => switch (type) {
        'h2' => h2,
        'h3' => h3,
        'q' => quote,
        'title' || 'h1' => title,
        'author' || 'by' => author,
        _ => body,
      };

  /// Space above / below a block of this type.
  (double, double) gapsFor(String type) => switch (type) {
        'h2' => (28, 10),
        'h3' => (20, 8),
        'q' => (14, 14),
        'li' || 'ol' => (0, 8),
        'title' || 'h1' => (21, 10), // 5px red bar + 16px gap drawn in the top gap
        'author' || 'by' => (0, 24),
        'img' => (12, 12),
        _ => (0, 14),
      };

  /// Horizontal space taken before the text (bullet, number, quote bar).
  double insetFor(String type) => switch (type) {
        'li' => 4 + 6 + 12,
        'ol' => 4 + 28 * scale,
        'q' => 3 + 16,
        _ => 0,
      };

  static const imageHeight = 200.0;
}

/// One block (or part of a block) placed on a page.
class PageItem {
  PageItem({
    required this.type,
    required this.runs,
    required this.blockIndex,
    required this.start,
    required this.gapTop,
    required this.gapBottom,
    this.number = 0,
    this.marker = true,
    this.url,
  });

  final String type;
  final List<Run> runs;

  /// Index in pack.blocks (-1 for the title/author header).
  final int blockIndex;

  /// Offset of this part inside the block's plain text.
  final int start;
  final double gapTop;
  final double gapBottom;
  final int number;

  /// False for the continuation of a list item split across pages.
  final bool marker;
  final String? url;
}

class BookPage {
  BookPage(this.items);
  final List<PageItem> items;

  /// Where this page starts: (block index, char offset) — survives
  /// re-pagination when the text size or the screen changes.
  (int, int) get anchor => items.isEmpty ? (-1, 0) : (items.first.blockIndex, items.first.start);
}

/// Splits a pack into pages that fit [size] exactly.
List<BookPage> paginate(Pack pack, ReaderStyles st, Size size, TextDirection dir) {
  final width = size.width, height = size.height - 1; // 1px rounding guard
  final pages = <BookPage>[];
  var cur = <PageItem>[];
  var used = 0.0;

  void newPage() {
    if (cur.isNotEmpty) pages.add(BookPage(cur));
    cur = [];
    used = 0;
  }

  TextPainter layout(List<Run> runs, String type) {
    final tp = TextPainter(
      text: spanOf(runs, st.styleFor(type)),
      textDirection: dir,
      textScaler: st.textScaler,
    );
    tp.layout(maxWidth: width - st.insetFor(type));
    return tp;
  }

  final bodyLine = layout(const [Run('A')], 'p').height;

  final entries = <(String, String, int)>[
    ('title', pack.title, -1),
    if (pack.author.isNotEmpty) ('author', pack.author, -1),
    for (var i = 0; i < pack.blocks.length; i++) (pack.blocks[i].type, pack.blocks[i].text, i),
  ];

  for (final (type, text, index) in entries) {
    final (gapTop, gapBottom) = st.gapsFor(type);
    final number = index >= 0 ? pack.listNumbers[index] : 0;

    if (type == 'img') {
      final need = (cur.isEmpty ? 0 : gapTop) + ReaderStyles.imageHeight;
      if (used + need > height) newPage();
      final top = cur.isEmpty ? 0.0 : gapTop;
      cur.add(PageItem(type: type, runs: const [], blockIndex: index, start: 0,
          gapTop: top, gapBottom: gapBottom, url: text));
      used += top + ReaderStyles.imageHeight + gapBottom;
      continue;
    }

    // Each magazine article starts on a new page.
    if (type == 'h1' && cur.isNotEmpty) newPage();

    var runs = parseRuns(text);
    var offset = 0;
    var first = true;
    final isHeading = type == 'h2' || type == 'h3' || type == 'title' || type == 'h1';

    while (true) {
      // Titles keep their top gap (it holds the red bar).
      final barred = type == 'title' || type == 'h1';
      var top = (cur.isEmpty && !barred) || !first ? 0.0 : gapTop;
      final tp = layout(runs, type);
      // Keep headings with at least two lines of what follows.
      final keep = isHeading ? 2 * bodyLine + gapBottom : 0;
      if (used + top + tp.height + keep <= height) {
        cur.add(PageItem(type: type, runs: runs, blockIndex: index, start: offset,
            gapTop: top, gapBottom: gapBottom, number: number, marker: first));
        used += top + tp.height + gapBottom;
        break;
      }
      if (isHeading) {
        if (cur.isEmpty) {
          // A heading taller than a page: place it anyway.
          cur.add(PageItem(type: type, runs: runs, blockIndex: index, start: offset,
              gapTop: 0, gapBottom: gapBottom, number: number));
          used += tp.height + gapBottom;
          break;
        }
        newPage();
        continue;
      }
      // Split the paragraph at the last line that still fits.
      final avail = height - used - top;
      var fitHeight = 0.0, fitLines = 0;
      for (final m in tp.computeLineMetrics()) {
        if (fitHeight + m.height > avail) break;
        fitHeight += m.height;
        fitLines++;
      }
      if (fitLines == 0) {
        if (cur.isEmpty) break; // cannot happen with sane sizes; avoid looping
        newPage();
        continue;
      }
      final pos = tp.getPositionForOffset(Offset(1, fitHeight - 1));
      final cut = tp.getLineBoundary(pos).end;
      if (cut <= 0 || cut >= runsLength(runs)) {
        newPage();
        continue;
      }
      cur.add(PageItem(type: type, runs: sliceRuns(runs, 0, cut), blockIndex: index,
          start: offset, gapTop: top, gapBottom: 0, number: number, marker: first));
      newPage();
      // Continue with the rest, without leading spaces.
      var rest = sliceRuns(runs, cut);
      var skipped = 0;
      while (rest.isNotEmpty && rest.first.text.trimLeft().length != rest.first.text.length) {
        final t = rest.first.text, trimmed = t.trimLeft();
        skipped += t.length - trimmed.length;
        rest = trimmed.isEmpty
            ? rest.sublist(1)
            : [Run(trimmed, bold: rest.first.bold, italic: rest.first.italic), ...rest.sublist(1)];
      }
      offset += cut + skipped;
      runs = rest;
      first = false;
      if (runs.isEmpty) break;
    }
  }
  newPage();
  return pages.isEmpty ? [BookPage([])] : pages;
}

/// Index of the page containing [anchor].
int pageForAnchor(List<BookPage> pages, (int, int) anchor) {
  var result = 0;
  for (var i = 0; i < pages.length; i++) {
    final (b, c) = pages[i].anchor;
    if (b < anchor.$1 || (b == anchor.$1 && c <= anchor.$2)) {
      result = i;
    } else {
      break;
    }
  }
  return result;
}
