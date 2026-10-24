import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../domain/frame_metrics.dart';

/// Live numbers for on-site threshold tuning.
class DebugMetricsPanel extends StatelessWidget {
  const DebugMetricsPanel({super.key, required this.metrics});
  final ValueListenable<FrameMetrics?> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<FrameMetrics?>(
      valueListenable: metrics,
      builder: (context, m, _) {
        if (m == null) return const SizedBox.shrink();
        final weakest = m.landmarks.isEmpty
            ? '—'
            : (m.landmarks.toList()
                  ..sort((a, b) => a.likelihood.compareTo(b.likelihood)))
                .first;
        final lines = [
          'analyses/s: ${m.analysesPerSecond}',
          'brightness: ${m.luma.mean.toStringAsFixed(0)}',
          'clipped: ${(m.luma.clippedFraction * 100).toStringAsFixed(0)}%',
          'centre/border: ${m.luma.centerToBorder.toStringAsFixed(2)}',
          'faces: ${m.faces}   persons: ${m.poses}',
          if (weakest is LandmarkPoint)
            'weakest: ${weakest.name} ${weakest.likelihood.toStringAsFixed(2)}',
          'issues: ${m.issues.isEmpty ? 'none' : m.issues.map((i) => i.name).join(', ')}',
        ];
        return Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              lines.join('\n'),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        );
      },
    );
  }
}

/// Draws the required body points on the preview: filled = ok, hollow = failing.
/// Accurate when cameraRotationDegrees is 0.
class LandmarkLayer extends StatelessWidget {
  const LandmarkLayer({
    super.key,
    required this.metrics,
    required this.okColor,
    required this.badColor,
  });

  final ValueListenable<FrameMetrics?> metrics;
  final Color okColor;
  final Color badColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FrameMetrics?>(
      valueListenable: metrics,
      builder: (context, m, _) => CustomPaint(
        size: Size.infinite,
        painter: _LandmarkPainter(
          points: m?.landmarks ?? const [],
          okColor: okColor,
          badColor: badColor,
        ),
      ),
    );
  }
}

class _LandmarkPainter extends CustomPainter {
  _LandmarkPainter({
    required this.points,
    required this.okColor,
    required this.badColor,
  });

  final List<LandmarkPoint> points;
  final Color okColor;
  final Color badColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in points) {
      if (p.x < 0 || p.y < 0) continue;
      final paint = Paint()
        ..color = p.ok ? okColor : badColor
        ..style = p.ok ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), 9, paint);
    }
  }

  @override
  bool shouldRepaint(_LandmarkPainter old) => old.points != points;
}
