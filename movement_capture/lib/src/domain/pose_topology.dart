import 'dart:ui' show Offset, Rect, lerpDouble;

import 'hand_topology.dart';

/// The 33 ML Kit pose points. Names match `PoseLandmarkType` exactly, so the
/// data layer maps by name and `domain` stays free of ML Kit.
enum PoseJoint {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

/// Body regions tracked separately. Used for colours (Revision 6) and for the
/// per-region tracking data (Revision 7).
enum BodyRegion { face, body, leftHand, rightHand, leftFoot, rightFoot }

/// Every ML Kit pose point belongs to exactly one region.
const Map<PoseJoint, BodyRegion> poseRegions = {
  PoseJoint.nose: BodyRegion.face,
  PoseJoint.leftEyeInner: BodyRegion.face,
  PoseJoint.leftEye: BodyRegion.face,
  PoseJoint.leftEyeOuter: BodyRegion.face,
  PoseJoint.rightEyeInner: BodyRegion.face,
  PoseJoint.rightEye: BodyRegion.face,
  PoseJoint.rightEyeOuter: BodyRegion.face,
  PoseJoint.leftEar: BodyRegion.face,
  PoseJoint.rightEar: BodyRegion.face,
  PoseJoint.leftMouth: BodyRegion.face,
  PoseJoint.rightMouth: BodyRegion.face,
  PoseJoint.leftShoulder: BodyRegion.body,
  PoseJoint.rightShoulder: BodyRegion.body,
  PoseJoint.leftElbow: BodyRegion.body,
  PoseJoint.rightElbow: BodyRegion.body,
  PoseJoint.leftHip: BodyRegion.body,
  PoseJoint.rightHip: BodyRegion.body,
  PoseJoint.leftKnee: BodyRegion.body,
  PoseJoint.rightKnee: BodyRegion.body,
  PoseJoint.leftWrist: BodyRegion.leftHand,
  PoseJoint.leftThumb: BodyRegion.leftHand,
  PoseJoint.leftIndex: BodyRegion.leftHand,
  PoseJoint.leftPinky: BodyRegion.leftHand,
  PoseJoint.rightWrist: BodyRegion.rightHand,
  PoseJoint.rightThumb: BodyRegion.rightHand,
  PoseJoint.rightIndex: BodyRegion.rightHand,
  PoseJoint.rightPinky: BodyRegion.rightHand,
  PoseJoint.leftAnkle: BodyRegion.leftFoot,
  PoseJoint.leftHeel: BodyRegion.leftFoot,
  PoseJoint.leftFootIndex: BodyRegion.leftFoot,
  PoseJoint.rightAnkle: BodyRegion.rightFoot,
  PoseJoint.rightHeel: BodyRegion.rightFoot,
  PoseJoint.rightFootIndex: BodyRegion.rightFoot,
};

class PoseConnection {
  const PoseConnection(this.from, this.to, this.region);
  final PoseJoint from;
  final PoseJoint to;

  /// Region whose colour the line uses.
  final BodyRegion region;
}

/// The standard pose skeleton (35 lines).
const List<PoseConnection> poseConnections = [
  // Face
  PoseConnection(PoseJoint.nose, PoseJoint.leftEyeInner, BodyRegion.face),
  PoseConnection(PoseJoint.leftEyeInner, PoseJoint.leftEye, BodyRegion.face),
  PoseConnection(PoseJoint.leftEye, PoseJoint.leftEyeOuter, BodyRegion.face),
  PoseConnection(PoseJoint.leftEyeOuter, PoseJoint.leftEar, BodyRegion.face),
  PoseConnection(PoseJoint.nose, PoseJoint.rightEyeInner, BodyRegion.face),
  PoseConnection(PoseJoint.rightEyeInner, PoseJoint.rightEye, BodyRegion.face),
  PoseConnection(PoseJoint.rightEye, PoseJoint.rightEyeOuter, BodyRegion.face),
  PoseConnection(PoseJoint.rightEyeOuter, PoseJoint.rightEar, BodyRegion.face),
  PoseConnection(PoseJoint.leftMouth, PoseJoint.rightMouth, BodyRegion.face),
  // Torso
  PoseConnection(
      PoseJoint.leftShoulder, PoseJoint.rightShoulder, BodyRegion.body),
  PoseConnection(PoseJoint.leftShoulder, PoseJoint.leftHip, BodyRegion.body),
  PoseConnection(PoseJoint.rightShoulder, PoseJoint.rightHip, BodyRegion.body),
  PoseConnection(PoseJoint.leftHip, PoseJoint.rightHip, BodyRegion.body),
  // Arms
  PoseConnection(PoseJoint.leftShoulder, PoseJoint.leftElbow, BodyRegion.body),
  PoseConnection(PoseJoint.leftElbow, PoseJoint.leftWrist, BodyRegion.body),
  PoseConnection(
      PoseJoint.rightShoulder, PoseJoint.rightElbow, BodyRegion.body),
  PoseConnection(PoseJoint.rightElbow, PoseJoint.rightWrist, BodyRegion.body),
  // Hands
  PoseConnection(PoseJoint.leftWrist, PoseJoint.leftThumb, BodyRegion.leftHand),
  PoseConnection(PoseJoint.leftWrist, PoseJoint.leftIndex, BodyRegion.leftHand),
  PoseConnection(PoseJoint.leftWrist, PoseJoint.leftPinky, BodyRegion.leftHand),
  PoseConnection(PoseJoint.leftIndex, PoseJoint.leftPinky, BodyRegion.leftHand),
  PoseConnection(
      PoseJoint.rightWrist, PoseJoint.rightThumb, BodyRegion.rightHand),
  PoseConnection(
      PoseJoint.rightWrist, PoseJoint.rightIndex, BodyRegion.rightHand),
  PoseConnection(
      PoseJoint.rightWrist, PoseJoint.rightPinky, BodyRegion.rightHand),
  PoseConnection(
      PoseJoint.rightIndex, PoseJoint.rightPinky, BodyRegion.rightHand),
  // Legs
  PoseConnection(PoseJoint.leftHip, PoseJoint.leftKnee, BodyRegion.body),
  PoseConnection(PoseJoint.leftKnee, PoseJoint.leftAnkle, BodyRegion.body),
  PoseConnection(PoseJoint.rightHip, PoseJoint.rightKnee, BodyRegion.body),
  PoseConnection(PoseJoint.rightKnee, PoseJoint.rightAnkle, BodyRegion.body),
  // Feet
  PoseConnection(PoseJoint.leftAnkle, PoseJoint.leftHeel, BodyRegion.leftFoot),
  PoseConnection(
      PoseJoint.leftHeel, PoseJoint.leftFootIndex, BodyRegion.leftFoot),
  PoseConnection(
      PoseJoint.leftAnkle, PoseJoint.leftFootIndex, BodyRegion.leftFoot),
  PoseConnection(
      PoseJoint.rightAnkle, PoseJoint.rightHeel, BodyRegion.rightFoot),
  PoseConnection(
      PoseJoint.rightHeel, PoseJoint.rightFootIndex, BodyRegion.rightFoot),
  PoseConnection(
      PoseJoint.rightAnkle, PoseJoint.rightFootIndex, BodyRegion.rightFoot),
];

/// One pose point in normalised upright-image coordinates (0–1).
class PosePoint {
  const PosePoint({
    required this.type,
    required this.x,
    required this.y,
    required this.likelihood,
  });

  final PoseJoint type;
  final double x;
  final double y;
  final double likelihood;

  BodyRegion get region => poseRegions[type]!;
}

/// What the overlay draws for one analysed frame.
class OverlayFrame {
  const OverlayFrame({
    this.pose = const [],
    this.faces = const [],
    this.faceContours = const [],
    this.hands = const [],
  });

  static const OverlayFrame empty = OverlayFrame();

  /// All detected pose points (up to 33) of the tracked person.
  final List<PosePoint> pose;

  /// Face boxes, normalised (0–1) in the upright image.
  final List<Rect> faces;

  /// Face step only: contour polylines, normalised.
  final List<List<Offset>> faceContours;

  /// Hands step only: tracked hands (21 points each).
  final List<HandSnapshot> hands;

  /// Positions glide from [a] to [b]. Points new in [b] appear at once.
  /// Contours are not interpolated (they change shape too often).
  static OverlayFrame lerp(OverlayFrame? a, OverlayFrame b, double t) {
    if (a == null || t >= 1) return b;
    final previous = {for (final p in a.pose) p.type: p};
    final pose = [
      for (final p in b.pose)
        if (previous[p.type] case final from?)
          PosePoint(
            type: p.type,
            x: lerpDouble(from.x, p.x, t)!,
            y: lerpDouble(from.y, p.y, t)!,
            likelihood: p.likelihood,
          )
        else
          p,
    ];
    final faces = a.faces.length == b.faces.length
        ? [
            for (var i = 0; i < b.faces.length; i++)
              Rect.lerp(a.faces[i], b.faces[i], t)!,
          ]
        : b.faces;
    final hands = a.hands.length == b.hands.length
        ? [
            for (var i = 0; i < b.hands.length; i++)
              HandSnapshot.lerp(a.hands[i], b.hands[i], t),
          ]
        : b.hands;
    return OverlayFrame(
      pose: pose,
      faces: faces,
      faceContours: b.faceContours,
      hands: hands,
    );
  }
}
