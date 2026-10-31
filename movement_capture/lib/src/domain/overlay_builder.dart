import 'body_sides.dart';
import 'hand_topology.dart';
import 'pose_topology.dart';

/// Builds what the skeleton layer draws for one frame.
///
/// - Face-region pose points are dropped: nothing is ever drawn on the face.
///   The face detector still runs for the quality checks and `landmarks.json`.
/// - Hands: when the person chose one hand only, just that hand is kept. The
///   side comes from [personSide], the same logic `handSideIssue` uses, so
///   mirrored and unmirrored frames both pick the right hand.
OverlayFrame buildOverlay({
  required List<PosePoint> pose,
  required List<HandSnapshot> hands,
  required SideChoice choice,
  required bool framesMirrored,
}) {
  return OverlayFrame(
    pose: [
      for (final p in pose)
        if (p.region != BodyRegion.face) p,
    ],
    hands: [
      for (final h in hands)
        if (choice == SideChoice.both ||
            choice.sides.map((s) => s.name).contains(
                personSide(h.handedness, framesMirrored: framesMirrored)))
          h,
    ],
  );
}
