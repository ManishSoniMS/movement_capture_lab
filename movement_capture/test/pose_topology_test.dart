import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:movement_capture/src/domain/pose_topology.dart';

void main() {
  test('every pose joint has exactly one region', () {
    for (final j in PoseJoint.values) {
      expect(poseRegions.containsKey(j), isTrue, reason: '$j has no region');
    }
    expect(poseRegions.length, PoseJoint.values.length);
  });

  test('joints match the ML Kit landmark types by name', () {
    expect(PoseJoint.values.map((j) => j.name).toSet(),
        PoseLandmarkType.values.map((t) => t.name).toSet());
  });

  test('35 connections, no self-links, no duplicates', () {
    expect(poseConnections.length, 35);
    final seen = <String>{};
    for (final c in poseConnections) {
      expect(c.from, isNot(c.to));
      final key = ([c.from.index, c.to.index]..sort()).join('-');
      expect(seen.add(key), isTrue, reason: 'duplicate $key');
    }
  });

  test('hand and foot lines only join points of that hand or foot', () {
    for (final c in poseConnections) {
      if (c.region == BodyRegion.body) continue;
      expect(poseRegions[c.from], c.region);
      expect(poseRegions[c.to], c.region);
    }
  });

  test('regions cover face, both hands and both feet', () {
    expect(poseRegions.values.toSet(), containsAll(BodyRegion.values));
  });

  test('lerp glides existing points and adds new ones at once', () {
    const a = OverlayFrame(pose: [
      PosePoint(type: PoseJoint.nose, x: 0, y: 0, likelihood: 1),
    ]);
    const b = OverlayFrame(pose: [
      PosePoint(type: PoseJoint.nose, x: 1, y: 1, likelihood: 1),
      PosePoint(type: PoseJoint.leftEye, x: 0.5, y: 0.5, likelihood: 1),
    ]);
    final mid = OverlayFrame.lerp(a, b, 0.5);
    final nose = mid.pose.firstWhere((p) => p.type == PoseJoint.nose);
    expect(nose.x, closeTo(0.5, 1e-9));
    expect(mid.pose.any((p) => p.type == PoseJoint.leftEye), isTrue);
    expect(OverlayFrame.lerp(null, b, 0.2).pose.length, 2);
  });

  test('face boxes glide when the count matches', () {
    const a = OverlayFrame(faces: [Rect.fromLTRB(0, 0, 0.2, 0.2)]);
    const b = OverlayFrame(faces: [Rect.fromLTRB(0.2, 0.2, 0.4, 0.4)]);
    expect(OverlayFrame.lerp(a, b, 0.5).faces.single.left, closeTo(0.1, 1e-9));
  });

  test('face contours are kept from the newer frame, not interpolated', () {
    const a = OverlayFrame(faceContours: [
      [Offset(0, 0), Offset(0.1, 0.1)],
    ]);
    const b = OverlayFrame(faceContours: [
      [Offset(0.5, 0.5), Offset(0.6, 0.6)],
    ]);
    expect(OverlayFrame.lerp(a, b, 0.5).faceContours, b.faceContours);
  });
}
