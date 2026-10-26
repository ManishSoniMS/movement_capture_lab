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
          'step: ${m.step.name}',
          'analyses/s: ${m.analysesPerSecond}',
          'rotation: ${m.rotationDegrees}°',
          'brightness: ${m.luma.mean.toStringAsFixed(0)}',
          'clipped: ${(m.luma.clippedFraction * 100).toStringAsFixed(0)}%',
          'centre/border: ${m.luma.centerToBorder.toStringAsFixed(2)}',
          'faces: ${m.faces}   persons: ${m.poses}',
          if (m.faceWidthFraction != null)
            'face width: ${(m.faceWidthFraction! * 100).toStringAsFixed(0)}%',
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
