import 'capture_issue.dart';
import 'luma_stats.dart';

/// Thrown by a [FrameAnalyzer] when the camera stream format is unusable.
class UnsupportedFrameFormat implements Exception {
  const UnsupportedFrameFormat(this.detail);
  final String detail;
  @override
  String toString() => 'UnsupportedFrameFormat: $detail';
}

/// One required body point, in normalised upright image coordinates (0–1).
/// x/y are -1 when ML Kit did not return the point.
class LandmarkPoint {
  const LandmarkPoint({
    required this.name,
    required this.x,
    required this.y,
    required this.likelihood,
    required this.ok,
  });
  final String name;
  final double x;
  final double y;
  final double likelihood;
  final bool ok;
}

class FrameMetrics {
  const FrameMetrics({
    required this.luma,
    required this.faces,
    required this.poses,
    required this.landmarks,
    required this.issues,
    required this.analysesPerSecond,
    required this.rotationDegrees,
  });
  final LumaStats luma;
  final int faces;
  final int poses;
  final List<LandmarkPoint> landmarks;
  final Set<CaptureIssue> issues;
  final int analysesPerSecond;

  /// Rotation (0/90/180/270) that was given to the detector for this frame.
  final int rotationDegrees;
}

class FrameCheck {
  const FrameCheck(
      {required this.issues, required this.at, required this.metrics});
  final Set<CaptureIssue> issues;
  final DateTime at;
  final FrameMetrics metrics;

  CaptureIssue? get topIssue {
    for (final issue in CaptureIssue.values) {
      if (issues.contains(issue)) return issue;
    }
    return null;
  }
}
