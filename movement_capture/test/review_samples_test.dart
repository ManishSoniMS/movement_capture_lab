import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/pose_topology.dart';
import 'package:movement_capture/src/domain/review_samples.dart';

OverlayFrame _f(double x) => OverlayFrame(pose: [
      PosePoint(type: PoseJoint.nose, x: x, y: 0.5, likelihood: 1),
    ]);

void main() {
  final samples = [
    TimedOverlay(0, _f(0.1)),
    TimedOverlay(70, _f(0.2)),
    TimedOverlay(140, _f(0.3)),
  ];

  test('picks the latest sample at or before the position', () {
    expect(overlayAt(samples, 0)!.pose.single.x, 0.1);
    expect(overlayAt(samples, 69)!.pose.single.x, 0.1);
    expect(overlayAt(samples, 70)!.pose.single.x, 0.2);
    expect(overlayAt(samples, 5000)!.pose.single.x, 0.3);
  });

  test('null when empty or before the first sample', () {
    expect(overlayAt(const [], 10), isNull);
    expect(overlayAt([TimedOverlay(50, _f(0.1))], 10), isNull);
  });
}
