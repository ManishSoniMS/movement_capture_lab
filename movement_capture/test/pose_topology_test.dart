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
}
