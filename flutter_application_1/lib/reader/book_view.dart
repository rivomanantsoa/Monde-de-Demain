import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Book-style pager: drag (or tap the right/left third) to turn pages; the
/// page folds along a line that follows the finger, showing the back of the
/// sheet, like a real book. Give it a new key when the pages change. Pure Flutter (clip + paint), no snapshots, so it
/// stays light on low-end phones.
class BookView extends StatefulWidget {
  const BookView({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    required this.initialPage,
    required this.onPageChanged,
    required this.paperColor,
    required this.backColor,
    this.rtl = false,
  });

  final int pageCount;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final Color paperColor;
  final Color backColor;

  /// Right-to-left books (Arabic…) turn the other way.
  final bool rtl;

  @override
  State<BookView> createState() => BookViewState();
}

enum _Turn { none, forward, backward }

class BookViewState extends State<BookView> with SingleTickerProviderStateMixin {
  late int _index = widget.initialPage.clamp(0, math.max(0, widget.pageCount - 1));
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  _Turn _turn = _Turn.none;
  Offset? _point; // where the folded corner currently is
  Offset _corner = Offset.zero; // the corner being lifted (right edge)
  Offset _dragStart = Offset.zero;
  Size _size = Size.zero;
  Animation<Offset>? _tween;
  bool _complete = false;

  int get index => _index;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_tween != null) setState(() => _point = _tween!.value);
    });
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool get _canForward => _index < widget.pageCount - 1;
  bool get _canBackward => _index > 0;

  /// Fully turned position: the corner lands on the far side, past the spine.
  Offset get _turned => Offset(-_size.width, _corner.dy);

  /// Paper cannot stretch: the corner stays within one page width of the
  /// spine point on the same edge.
  Offset _constrain(Offset p) {
    final spine = Offset(0, _corner.dy);
    final v = p - spine;
    final d = v.distance;
    if (d > _size.width) p = spine + v * (_size.width / d);
    return Offset(p.dx.clamp(-_size.width, _size.width), p.dy);
  }

  void _start(_Turn turn, double y) {
    _anim.stop();
    _turn = turn;
    _corner = Offset(_size.width, y > _size.height / 2 ? _size.height : 0);
  }

  // ---------------------------------------------------------------- gestures
  void _onDragStart(DragStartDetails d) {
    if (_anim.isAnimating) return;
    _dragStart = d.localPosition;
    _turn = _Turn.none;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_anim.isAnimating) return;
    final delta = d.localPosition - _dragStart;
    if (_turn == _Turn.none) {
      if (delta.dx < -4 && _canForward) {
        _start(_Turn.forward, _dragStart.dy);
      } else if (delta.dx > 4 && _canBackward) {
        _start(_Turn.backward, _dragStart.dy);
      } else {
        return;
      }
    }
    setState(() {
      _point = _turn == _Turn.forward
          // the lifted corner follows the finger
          ? _constrain(_corner + delta)
          // the previous page unfolds from the far side
          : _constrain(Offset(-_size.width + 2 * delta.dx, _corner.dy + delta.dy * 0.5));
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_turn == _Turn.none || _point == null) return;
    final v = d.velocity.pixelsPerSecond.dx;
    final p = _point!;
    if (_turn == _Turn.forward) {
      final go = v < -300 || (v < 300 && p.dx < _size.width * 0.45);
      _animateTo(go ? _turned : _corner, complete: go);
    } else {
      final go = v > 300 || (v > -300 && p.dx > -_size.width * 0.55);
      _animateTo(go ? _corner : _turned, complete: go);
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (_anim.isAnimating) return;
    final x = d.localPosition.dx;
    if (x > _size.width * 2 / 3) {
      next();
    } else if (x < _size.width / 3) {
      previous();
    }
  }

  /// Turns to the next page with the full fold animation.
  void next() {
    if (!_canForward || _anim.isAnimating) return;
    _start(_Turn.forward, _size.height);
    _point = _corner - const Offset(1, 1);
    _animateTo(_turned, complete: true);
  }

  void previous() {
    if (!_canBackward || _anim.isAnimating) return;
    _start(_Turn.backward, _size.height);
    _point = _turned;
    _animateTo(_corner - const Offset(0.5, 0.5), complete: true);
  }

  void _animateTo(Offset target, {required bool complete}) {
    _complete = complete;
    _tween = Tween<Offset>(begin: _point, end: target)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_anim);
    _anim.forward(from: 0);
  }

  void _finish() {
    setState(() {
      if (_complete) {
        _index += _turn == _Turn.forward ? 1 : -1;
        widget.onPageChanged(_index);
      }
      _turn = _Turn.none;
      _point = null;
      _tween = null;
    });
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    Widget page(int i) => RepaintBoundary(
          key: ValueKey(i),
          child: ColoredBox(
            color: widget.paperColor,
            // Undo the RTL mirror for the page contents.
            child: widget.rtl
                ? Transform.flip(flipX: true, child: widget.pageBuilder(context, i))
                : widget.pageBuilder(context, i),
          ),
        );

    Widget body = LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      final p = _point;
      Widget content;
      if (_turn == _Turn.none || p == null) {
        content = page(_index);
      } else {
        final under = _turn == _Turn.forward ? _index + 1 : _index;
        final top = _turn == _Turn.forward ? _index : _index - 1;
        final fold = _Fold.compute(_size, _corner, p);
        content = Stack(
          fit: StackFit.expand,
          children: [
            page(under),
            ClipPath(clipper: _PolygonClipper(fold.kept), child: page(top)),
            IgnorePointer(
              child: CustomPaint(
                painter: _FoldPainter(fold, widget.backColor, widget.paperColor),
              ),
            ),
          ],
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onTapUp: _onTapUp,
        child: content,
      );
    });
    // Mirror the whole book for RTL so it turns from the left.
    if (widget.rtl) body = Transform.flip(flipX: true, child: body);
    return ClipRect(child: body);
  }
}

/// Geometry of a fold: the fold line is the perpendicular bisector between
/// the lifted corner and where it is now.
class _Fold {
  _Fold(this.kept, this.folded, this.flap, this.lineA, this.lineB, this.normal, this.tip, this.progress);

  final List<Offset> kept; // part of the page still flat
  final List<Offset> folded; // part lifted (reveals the page below)
  final List<Offset> flap; // the lifted part, flipped over (back of sheet)
  final Offset lineA, lineB; // fold line end points (approx.)
  final Offset normal; // unit vector from the fold line towards the corner
  final Offset tip; // where the corner is
  final double progress; // 0 = flat, 1 = fully turned

  static _Fold compute(Size size, Offset corner, Offset p) {
    final rect = [Offset.zero, Offset(size.width, 0), Offset(size.width, size.height), Offset(0, size.height)];
    var d = corner - p;
    if (d.distance < 0.5) d = const Offset(0.5, 0.5);
    final n = d / d.distance;
    final m = (corner + p) / 2;
    double side(Offset x) => (x - m).dx * n.dx + (x - m).dy * n.dy;

    final kept = _clip(rect, (x) => -side(x));
    final folded = _clip(rect, side);
    final flap = [for (final x in folded) x - n * (2 * side(x))];
    final t = Offset(-n.dy, n.dx) * (size.width + size.height);
    return _Fold(kept, folded, flap, m - t, m + t, n, p,
        ((corner.dx - p.dx) / (2 * size.width)).clamp(0.0, 1.0));
  }

  /// Sutherland–Hodgman clip of a polygon by the half-plane f(x) >= 0.
  static List<Offset> _clip(List<Offset> poly, double Function(Offset) f) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final fa = f(a), fb = f(b);
      if (fa >= 0) out.add(a);
      if ((fa >= 0) != (fb >= 0)) {
        final t = fa / (fa - fb);
        out.add(a + (b - a) * t);
      }
    }
    return out;
  }
}

Path _path(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

class _PolygonClipper extends CustomClipper<Path> {
  _PolygonClipper(this.points);
  final List<Offset> points;

  @override
  Path getClip(Size size) => _path(points);

  @override
  bool shouldReclip(_PolygonClipper old) => true;
}

class _FoldPainter extends CustomPainter {
  _FoldPainter(this.fold, this.backColor, this.paperColor);
  final _Fold fold;
  final Color backColor;
  final Color paperColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (fold.folded.length < 3) return;
    final n = fold.normal;
    final onLine = (fold.lineA + fold.lineB) / 2;
    // Shadow strength fades in at the start and out at the end of a turn.
    final k = math.sin(fold.progress * math.pi).clamp(0.15, 1.0);

    // 1. Shadow cast on the revealed page, along the fold line.
    final revealed = _path(fold.folded);
    canvas.save();
    canvas.clipPath(revealed);
    final w = 24 + 40 * k;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.black.withValues(alpha: 0.35 * k), Colors.black.withValues(alpha: 0)],
        ).createShader(Rect.fromPoints(onLine, onLine + n * w)),
    );
    canvas.restore();

    if (fold.flap.length < 3) return;
    final flap = _path(fold.flap);

    // 2. The flap's own shadow on the flat page.
    canvas.drawShadow(flap, Colors.black, 6 * k, false);

    // 3. The back of the sheet, shaded to suggest the paper's curve: darker
    //    at the fold, light in the middle, slightly darker at the tip.
    final tip = fold.tip;
    final span = math.max(1.0, ((tip - onLine).dx * -n.dx + (tip - onLine).dy * -n.dy).abs());
    canvas.drawPath(
      flap,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(backColor, Colors.black, 0.18)!,
            Color.lerp(backColor, paperColor, 0.6)!,
            backColor,
            Color.lerp(backColor, Colors.black, 0.08)!,
          ],
          stops: const [0, 0.25, 0.7, 1],
        ).createShader(Rect.fromPoints(onLine, onLine - n * span)),
    );
    // Thin edge line where the sheet bends.
    canvas.drawPath(
      flap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_FoldPainter old) => true;
}
