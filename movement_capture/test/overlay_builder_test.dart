import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/body_sides.dart';
import 'package:movement_capture/src/domain/hand_topology.dart';
import 'package:movement_capture/src/domain/overlay_builder.dart';
import 'package:movement_capture/src/domain/pose_topology.dart';

HandSnapshot _hand(String handedness) => HandSnapshot(
      handedness: handedness,
      score: 1,
      points: [for (var i = 0; i < 21; i++) Offset(i / 21, 0.5)],
      depth: List.filled(21, 0),
    );

PosePoint _p(PoseJoint j) => PosePoint(type: j, x: 0.5, y: 0.5, likelihood: 1);

void main() {
  group('face is never drawn', () {
    test('face-region pose points are dropped, the rest kept', () {
      final frame = buildOverlay(
        pose: [
          _p(PoseJoint.nose),
          _p(PoseJoint.leftEye),
          _p(PoseJoint.leftMouth),
          _p(PoseJoint.leftShoulder),
          _p(PoseJoint.leftAnkle),
          _p(PoseJoint.rightIndex),
        ],
        hands: const [],
        choice: SideChoice.both,
        framesMirrored: false,
      );
      expect(frame.pose.map((p) => p.type), [
        PoseJoint.leftShoulder,
        PoseJoint.leftAnkle,
        PoseJoint.rightIndex,
      ]);
      expect(frame.pose.any((p) => p.region == BodyRegion.face), isFalse);
    });

    test('OverlayFrame has no face boxes or contours', () {
      // Compile-time guard: the type only carries pose and hands.
      const f = OverlayFrame();
      expect(f.pose, isEmpty);
      expect(f.hands, isEmpty);
    });
  });

  group('one hand chosen draws only that hand', () {
    // MediaPipe labels as if mirrored. Unmirrored frames: label "Left" is the
    // person's RIGHT hand. Mirrored frames: label is the person's own side.
    List<String> drawn(SideChoice c, {required bool mirrored}) => [
          for (final h in buildOverlay(
            pose: const [],
            hands: [_hand('Left'), _hand('Right')],
            choice: c,
            framesMirrored: mirrored,
          ).hands)
            h.handedness,
        ];

    test('both draws both', () {
      expect(drawn(SideChoice.both, mirrored: false), ['Left', 'Right']);
      expect(drawn(SideChoice.both, mirrored: true), ['Left', 'Right']);
    });

    test('right only, unmirrored: the "Left" label is the right hand', () {
      expect(drawn(SideChoice.rightOnly, mirrored: false), ['Left']);
    });

    test('right only, mirrored: the "Right" label is the right hand', () {
      expect(drawn(SideChoice.rightOnly, mirrored: true), ['Right']);
    });

    test('left only, unmirrored', () {
      expect(drawn(SideChoice.leftOnly, mirrored: false), ['Right']);
    });

    test('left only, mirrored', () {
      expect(drawn(SideChoice.leftOnly, mirrored: true), ['Left']);
    });
  });

  test('lerp keeps pose and hands only', () {
    final a = OverlayFrame(pose: [_p(PoseJoint.leftShoulder)]);
    final b = OverlayFrame(pose: [
      PosePoint(type: PoseJoint.leftShoulder, x: 1, y: 1, likelihood: 1),
    ]);
    expect(OverlayFrame.lerp(a, b, 0.5).pose.single.x, closeTo(0.75, 1e-9));
  });
}
