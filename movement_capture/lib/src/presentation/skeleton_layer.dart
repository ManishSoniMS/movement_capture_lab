import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/frame_metrics.dart';
import '../domain/hand_topology.dart';
import '../domain/pose_topology.dart';

class SkeletonColors {
  const SkeletonColors({
    required this.body,
    required this.hand,
    required this.foot,
  });

  final Color body;
  final Color hand;
  final Color foot;

  Color forRegion(BodyRegion r) => switch (r) {
        // Face points are never drawn (see buildOverlay); body colour is only
        // a total-function fallback.
        BodyRegion.body || BodyRegion.face => body,
        BodyRegion.leftHand || BodyRegion.rightHand => hand,
        BodyRegion.leftFoot || BodyRegion.rightFoot => foot,
      };
}

/// Draws the body skeleton and hand points, gliding between analysed frames.
/// Never draws on the face.
/// Sits inside the CameraPreview (and its mirror transform), so normalised
/// coordinates map directly onto the preview area.
class SkeletonLayer extends StatefulWidget {
  const SkeletonLayer({
    super.key,
    required this.frames,
    required this.colors,
    required this.minLikelihood,
    required this.transition,
    this.drawMarks = true,
    this.debugMetrics,
    this.debugBadColor,
  });

  final ValueListenable<OverlayFrame?> frames;
  final SkeletonColors colors;
  final double minLikelihood;
  final Duration transition;

  /// false = draw no marks at all (`showSkeleton` off); only the debug rings
  /// remain when [debugMetrics] is set.
  final bool drawMarks;

  /// When set (debug overlay on), failing required points get a ring.
  final ValueListenable<FrameMetrics?>? debugMetrics;
  final Color? debugBadColor;

  @override
  State<SkeletonLayer> createState() => _SkeletonLayerState();
}

class _SkeletonLayerState extends State<SkeletonLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: widget.transition, value: 1);
  OverlayFrame? _from;
  OverlayFrame? _to;

  @override
  void initState() {
    super.initState();
    _to = widget.frames.value;
    widget.frames.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(SkeletonLayer old) {
    super.didUpdateWidget(old);
    if (old.frames != widget.frames) {
      old.frames.removeListener(_onFrame);
      widget.frames.addListener(_onFrame);
      _onFrame();
    }
    if (old.transition != widget.transition) {
      _anim.duration = widget.transition;
    }
  }

  void _onFrame() {
    final next = widget.frames.value;
    if (next == null) {
      setState(() {
        _from = null;
        _to = null;
        _anim.value = 1;
      });
      return;
    }
    _from = _current();
    _to = next;
    _anim.forward(from: 0);
  }

  OverlayFrame? _current() {
    final to = _to;
    if (to == null) return null;
    return OverlayFrame.lerp(_from, to, Curves.easeOut.transform(_anim.value));
  }

  @override
  void dispose() {
    widget.frames.removeListener(_onFrame);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repaint = widget.debugMetrics == null
        ? _anim
        : Listenable.merge([_anim, widget.debugMetrics!]);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SkeletonPainter(
            repaint: repaint,
            current: _current,
            colors: widget.colors,
            minLikelihood: widget.minLikelihood,
            drawMarks: widget.drawMarks,
            debugMetrics: widget.debugMetrics,
            debugBadColor: widget.debugBadColor ?? Colors.red,
          ),
        ),
      ),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  _SkeletonPainter({
    required Listenable repaint,
    required this.current,
    required this.colors,
    required this.minLikelihood,
    required this.drawMarks,
    required this.debugMetrics,
    required this.debugBadColor,
  }) : super(repaint: repaint);

  final OverlayFrame? Function() current;
  final SkeletonColors colors;
  final double minLikelihood;
  final bool drawMarks;
  final ValueListenable<FrameMetrics?>? debugMetrics;
  final Color debugBadColor;

  static const double _margin = 0.02; // allow points just at the edge

  bool _inside(double x, double y) =>
      x >= -_margin && x <= 1 + _margin && y >= -_margin && y <= 1 + _margin;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = drawMarks ? current() : null;
    final stroke = (size.shortestSide / 160).clamp(2.5, 6.0).toDouble();
    final radius = stroke * 1.4;
    Offset at(double x, double y) => Offset(x * size.width, y * size.height);

    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke + 3;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    final dot = Paint()..style = PaintingStyle.fill;
    final dotOutline = Paint()..color = Colors.black.withValues(alpha: 0.45);

    if (frame != null) {
      final visible = {
        for (final p in frame.pose)
          if (p.likelihood >= minLikelihood && _inside(p.x, p.y)) p.type: p,
      };

      // Less certain points are drawn more transparent (0.35 → 1.0 between
      // minLikelihood and 0.7), so hands and feet stay visible while moving.
      double alphaOf(double likelihood) {
        if (likelihood >= 0.7) return 1;
        final span = 0.7 - minLikelihood;
        if (span <= 0) return 1;
        final t = ((likelihood - minLikelihood) / span).clamp(0.0, 1.0);
        return 0.35 + 0.65 * t;
      }

      for (final c in poseConnections) {
        final a = visible[c.from];
        final b = visible[c.to];
        if (a == null || b == null) continue;
        final alpha =
            alphaOf(a.likelihood < b.likelihood ? a.likelihood : b.likelihood);
        final p1 = at(a.x, a.y), p2 = at(b.x, b.y);
        outline.color = Colors.black.withValues(alpha: 0.45 * alpha);
        canvas.drawLine(p1, p2, outline);
        line.color = colors.forRegion(c.region).withValues(alpha: alpha);
        canvas.drawLine(p1, p2, line);
      }

      for (final p in visible.values) {
        final o = at(p.x, p.y);
        final alpha = alphaOf(p.likelihood);
        dotOutline.color = Colors.black.withValues(alpha: 0.45 * alpha);
        canvas.drawCircle(o, radius + 1.5, dotOutline);
        dot.color = colors.forRegion(p.region).withValues(alpha: alpha);
        canvas.drawCircle(o, radius, dot);
      }
      outline.color = Colors.black.withValues(alpha: 0.45); // for hand lines

      for (final hand in frame.hands) {
        if (!hand.isComplete) continue;
        final pts = [for (final p in hand.points) at(p.dx, p.dy)];
        line.color = colors.hand;
        for (final (a, b) in handConnections) {
          canvas.drawLine(pts[a], pts[b], outline);
          canvas.drawLine(pts[a], pts[b], line);
        }
        dot.color = colors.hand;
        dotOutline.color = Colors.black.withValues(alpha: 0.45);
        for (final o in pts) {
          canvas.drawCircle(o, radius * 0.8 + 1.5, dotOutline);
          canvas.drawCircle(o, radius * 0.8, dot);
        }
      }
    }

    // Debug: ring around required points that fail the in-frame check.
    final metrics = debugMetrics?.value;
    if (metrics != null) {
      final ring = Paint()
        ..color = debugBadColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;
      for (final p in metrics.landmarks) {
        if (p.ok || p.x < 0 || p.y < 0) continue;
        canvas.drawCircle(at(p.x, p.y), radius * 2.2, ring);
      }
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.colors != colors ||
      old.minLikelihood != minLikelihood ||
      old.drawMarks != drawMarks ||
      old.debugMetrics != debugMetrics;
}
