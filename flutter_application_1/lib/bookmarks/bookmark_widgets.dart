import 'package:flutter/material.dart';

import '../theme.dart';
import 'bookmarks.dart';

/// Red ribbon hanging from the top edge of a page, like a book's ribbon.
class BookmarkRibbon extends StatelessWidget {
  const BookmarkRibbon({super.key, this.width = 16, this.height = 38});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: _RibbonPainter(),
      );
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final notch = s.width * 0.45;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height - notch)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = Brand.red);
    // subtle fold highlight
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width * 0.3, s.height - notch),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => false;
}

/// Wraps a paragraph: long-press marks it, and a small ribbon is drawn in
/// the margin (start side) when it holds the mark. The margin marker sits
/// outside the child's box, so the text layout is unchanged.
class MarkableParagraph extends StatelessWidget {
  const MarkableParagraph({
    super.key,
    required this.marked,
    required this.onMark,
    required this.child,
    this.markerOffset = 14,
    this.markerTop = 2,
  });

  final bool marked;
  final VoidCallback onMark;
  final Widget child;

  /// Distance from the text's start edge to the marker (in the page margin).
  final double markerOffset;

  /// Vertical position of the marker (to align it with the first text line).
  final double markerTop;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onMark,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (marked)
            PositionedDirectional(
              start: -markerOffset,
              top: markerTop,
              child: const IgnorePointer(child: BookmarkRibbon(width: 8, height: 18)),
            ),
        ],
      ),
    );
  }
}

/// Labels used by [BookmarkButton] (kept separate so any screen can reuse it
/// with its own translations).
class BookmarkLabels {
  const BookmarkLabels({
    required this.bookmark,
    required this.placeHere,
    required this.goTo,
    required this.remove,
    required this.hint,
  });
  final String bookmark, placeHere, goTo, remove, hint;
}

/// App-bar action: places the mark at the current position, or — when a
/// mark exists — offers go to / move here / remove.
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({
    super.key,
    required this.mark,
    required this.labels,
    required this.onPlaceHere,
    required this.onGoTo,
    required this.onRemove,
  });

  final ReadingMark? mark;
  final BookmarkLabels labels;
  final VoidCallback onPlaceHere;
  final VoidCallback onGoTo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (mark == null) {
      return IconButton(
        tooltip: labels.placeHere,
        icon: const Icon(Icons.bookmark_border),
        onPressed: onPlaceHere,
      );
    }
    return PopupMenuButton<int>(
      tooltip: labels.bookmark,
      icon: const Icon(Icons.bookmark, color: Brand.redOnDark),
      onSelected: (v) => [onGoTo, onPlaceHere, onRemove][v](),
      itemBuilder: (_) => [
        PopupMenuItem(value: 0, child: ListTile(leading: const Icon(Icons.bookmark), title: Text(labels.goTo))),
        PopupMenuItem(value: 1, child: ListTile(leading: const Icon(Icons.bookmark_add_outlined), title: Text(labels.placeHere))),
        PopupMenuItem(value: 2, child: ListTile(leading: const Icon(Icons.bookmark_remove_outlined), title: Text(labels.remove))),
        PopupMenuItem(
          enabled: false,
          child: Text(labels.hint, style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ),
      ],
    );
  }
}
