import 'dart:ui' show Offset, Rect;

/// One face, normalised (0–1) in the upright image.
///
/// Landmark and contour keys are ML Kit's `FaceLandmarkType` and
/// `FaceContourType` names, kept as strings so the domain stays free of ML Kit.
class FaceSnapshot {
  const FaceSnapshot({
    required this.box,
    this.landmarks = const {},
    this.contours = const {},
    this.headEulerX,
    this.headEulerY,
    this.headEulerZ,
  });

  final Rect box;
  final Map<String, Offset> landmarks;
  final Map<String, List<Offset>> contours;
  final double? headEulerX;
  final double? headEulerY;
  final double? headEulerZ;
}
