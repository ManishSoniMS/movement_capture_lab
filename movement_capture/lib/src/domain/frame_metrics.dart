import 'dart:ui' show Size;

import 'capture_issue.dart';
import 'capture_step.dart';
import 'face_snapshot.dart';
import 'hand_topology.dart';
import 'luma_stats.dart';
import 'pose_topology.dart';

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
    required this.step,
    required this.luma,
    required this.faces,
    required this.poses,
    required this.landmarks,
    required this.issues,
    required this.analysesPerSecond,
    required this.rotationDegrees,
    this.faceWidthFraction,
    this.hands = 0,
    this.handTracking = false,
  });
  final CaptureStep step;
  final LumaStats luma;
  final int faces;
  final int poses;
  final List<LandmarkPoint> landmarks;
  final Set<CaptureIssue> issues;
  final int analysesPerSecond;

  /// Rotation (0/90/180/270) that was given to the detector for this frame.
  final int rotationDegrees;

  /// Face step: width of the found face as a share of the frame width.
  final double? faceWidthFraction;

  /// Hands step: number of hands found.
  final int hands;

  /// True while MediaPipe hand tracking is active in this step.
  final bool handTracking;
}

class FrameCheck {
  const FrameCheck({
    required this.issues,
    required this.at,
    required this.metrics,
    this.uprightSize = Size.zero,
    this.rotationDegrees = 0,
    this.overlay = OverlayFrame.empty,
    this.pose = const [],
    this.faceCount = 0,
    this.face,
    this.hands = const [],
  });
  final Set<CaptureIssue> issues;
  final DateTime at;
  final FrameMetrics metrics;

  /// Size of the upright (rotated) image the normalised points refer to.
  final Size uprightSize;
  final int rotationDegrees;

  /// What the skeleton layer draws for this frame.
  final OverlayFrame overlay;

  /// All pose points of the tracked person (fullBody step).
  final List<PosePoint> pose;
  final int faceCount;

  /// The single face found (face step), with landmarks and contours.
  final FaceSnapshot? face;

  /// Hands step: tracked hands (21 points each).
  final List<HandSnapshot> hands;

  CaptureIssue? get topIssue {
    for (final issue in CaptureIssue.values) {
      if (issues.contains(issue)) return issue;
    }
    return null;
  }
}
