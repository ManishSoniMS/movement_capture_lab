import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/frame_metrics.dart';
import 'package:movement_capture/src/domain/luma_stats.dart';

FrameMetrics _metrics(Set<CaptureIssue> issues) => FrameMetrics(
      step: CaptureStep.fullBody,
      luma: const LumaStats(mean: 100, clippedFraction: 0, centerToBorder: 1),
      faces: 1,
      poses: 1,
      landmarks: const [],
      issues: issues,
      analysesPerSecond: 6,
      rotationDegrees: 0,
    );

void main() {
  test('topIssue is null when no issue', () {
    final check = FrameCheck(
      issues: const {},
      at: DateTime(2026),
      metrics: _metrics(const {}),
    );
    expect(check.topIssue, isNull);
  });

  test('topIssue follows CaptureIssue declaration order', () {
    final check = FrameCheck(
      issues: const {CaptureIssue.tooBright, CaptureIssue.outOfFrame},
      at: DateTime(2026),
      metrics: _metrics(const {}),
    );
    expect(check.topIssue, CaptureIssue.outOfFrame);
  });

  test('face and hand issues rank between person and lighting issues', () {
    expect(
      CaptureIssue.values,
      [
        CaptureIssue.multiplePeople,
        CaptureIssue.noPerson,
        CaptureIssue.noFace,
        CaptureIssue.noHands,
        CaptureIssue.oneHand,
        CaptureIssue.showLeftHand,
        CaptureIssue.showRightHand,
        CaptureIssue.outOfFrame,
        CaptureIssue.faceTooFar,
        CaptureIssue.tooDark,
        CaptureIssue.tooBright,
        CaptureIssue.backlit,
      ],
    );
    final check = FrameCheck(
      issues: const {CaptureIssue.tooDark, CaptureIssue.faceTooFar},
      at: DateTime(2026),
      metrics: _metrics(const {}),
    );
    expect(check.topIssue, CaptureIssue.faceTooFar);
  });
}
