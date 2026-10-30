import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

void main() {
  test('maxDuration is clamped to 5–30 s', () {
    expect(
        MovementCaptureConfig(maxDuration: const Duration(seconds: 45))
            .maxDuration,
        const Duration(seconds: 30));
    expect(
        MovementCaptureConfig(maxDuration: const Duration(seconds: 2))
            .maxDuration,
        const Duration(seconds: 5));
    expect(
        MovementCaptureConfig(maxDuration: const Duration(seconds: 12))
            .maxDuration,
        const Duration(seconds: 12));
  });

  test('rejects an invalid rotation', () {
    expect(() => MovementCaptureConfig(cameraRotationDegrees: 45),
        throwsA(isA<AssertionError>()));
  });

  test('camera defaults: no preferred id, mirroring left to the platform', () {
    final c = MovementCaptureConfig();
    expect(c.preferredCameraId, isNull);
    expect(c.mirrorExternalPreview, isNull);
    expect(c.mirrorFrontPreview, isNull);
    expect(c.mirrorBackPreview, isNull);
    expect(c.allowRecordingWithoutLiveChecks, isTrue);
    expect(c.orientation, CaptureOrientation.auto);
  });

  test('mirroring defaults: USB on, front and back off, on both platforms', () {
    final c = MovementCaptureConfig();
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(c.mirrorPreviewFor(CameraKind.external, p), isTrue);
      expect(c.mirrorPreviewFor(CameraKind.front, p), isFalse);
      expect(c.mirrorPreviewFor(CameraKind.back, p), isFalse);
    }
  });

  test('skeleton flip only for the Android front camera', () {
    final c = MovementCaptureConfig();
    expect(c.overlayFlipFor(CameraKind.front, TargetPlatform.android), isTrue);
    expect(c.overlayFlipFor(CameraKind.front, TargetPlatform.iOS), isFalse);
    expect(
        c.overlayFlipFor(CameraKind.external, TargetPlatform.android), isFalse);
    expect(c.overlayFlipFor(CameraKind.back, TargetPlatform.android), isFalse);
  });

  test('analysis interval: 66 ms, 150 ms on low-memory devices, override wins',
      () {
    expect(
        MovementCaptureConfig()
            .effectiveAnalysisInterval(lowMemoryDevice: false),
        const Duration(milliseconds: 66));
    expect(
        MovementCaptureConfig()
            .effectiveAnalysisInterval(lowMemoryDevice: true),
        const Duration(milliseconds: 150));
    expect(
        MovementCaptureConfig(
                analysisInterval: const Duration(milliseconds: 100))
            .effectiveAnalysisInterval(lowMemoryDevice: true),
        const Duration(milliseconds: 100));
  });

  test('rotation override accepts null and quarter turns only', () {
    expect(MovementCaptureConfig().cameraRotationDegrees, isNull);
    expect(
        MovementCaptureConfig(cameraRotationDegrees: 90).cameraRotationDegrees,
        90);
  });

  test('landmark likelihood default', () {
    expect(MovementCaptureConfig().minLandmarkLikelihood, 0.5);
  });

  test('explicit mirroring overrides the platform default', () {
    final c = MovementCaptureConfig(mirrorFrontPreview: true);
    expect(c.mirrorPreviewFor(CameraKind.front, TargetPlatform.iOS), isTrue);
  });

  test('auto orientation: phones portrait, tablets landscape', () {
    final c = MovementCaptureConfig();
    expect(c.orientationsFor(390), [DeviceOrientation.portraitUp]);
    expect(c.orientationsFor(800), [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final forced =
        MovementCaptureConfig(orientation: CaptureOrientation.landscape);
    expect(forced.orientationsFor(390).first, DeviceOrientation.landscapeLeft);
  });

  test('steps: duplicates removed, empty means full body only', () {
    expect(
      MovementCaptureConfig(steps: const [
        CaptureStep.face,
        CaptureStep.fullBody,
        CaptureStep.face,
      ]).effectiveSteps,
      [CaptureStep.face, CaptureStep.fullBody],
    );
    expect(MovementCaptureConfig(steps: const []).effectiveSteps,
        [CaptureStep.fullBody]);
  });

  test('default steps run full body, face, hands, feet in that order', () {
    expect(MovementCaptureConfig().effectiveSteps, CaptureStep.values);
  });

  test('durations: full body uses maxDuration, others 10 s, all clamped', () {
    final c = MovementCaptureConfig(
      maxDuration: const Duration(seconds: 20),
      stepDurations: const {CaptureStep.hands: Duration(seconds: 60)},
    );
    expect(c.durationFor(CaptureStep.fullBody), const Duration(seconds: 20));
    expect(c.durationFor(CaptureStep.face), const Duration(seconds: 10));
    expect(c.durationFor(CaptureStep.hands), const Duration(seconds: 30));
  });

  test('only face, hands and feet are skippable by default', () {
    final c = MovementCaptureConfig();
    expect(c.skippableSteps, {
      CaptureStep.face,
      CaptureStep.hands,
      CaptureStep.feet,
    });
    expect(c.stepCameras, isEmpty);
    expect(c.faceMinWidthFraction, 0.28);
  });

  test('countdown default depends on mode', () {
    expect(
        MovementCaptureConfig().effectiveCountdown, const Duration(seconds: 3));
    expect(
        MovementCaptureConfig(mode: CaptureMode.selfGuided).effectiveCountdown,
        const Duration(seconds: 5));
    expect(
        MovementCaptureConfig(
                mode: CaptureMode.selfGuided,
                countdown: const Duration(seconds: 2))
            .effectiveCountdown,
        const Duration(seconds: 2));
  });

  test('voice speaks in self-guided mode, in assisted only when asked', () {
    expect(MovementCaptureConfig().speaks, isFalse);
    expect(MovementCaptureConfig(voiceInAssisted: true).speaks, isTrue);
    expect(MovementCaptureConfig(mode: CaptureMode.selfGuided).speaks, isTrue);
  });

  test('hand tracking defaults on and needs both hands', () {
    final c = MovementCaptureConfig();
    expect(c.handTracking, isTrue);
    expect(c.requireBothHands, isTrue);
  });

  test('hands step records landmarks and uses MediaPipe', () {
    expect(CaptureStep.hands.usesHands, isTrue);
    expect(CaptureStep.hands.recordsLandmarks, isTrue);
    expect(CaptureStep.feet.usesHands, isFalse);
    expect(CaptureStep.feet.recordsLandmarks, isFalse);
  });

  test('hand issues rank after noFace and before outOfFrame', () {
    final order = CaptureIssue.values;
    expect(order.indexOf(CaptureIssue.noHands), greaterThan(order.indexOf(CaptureIssue.noFace)));
    expect(order.indexOf(CaptureIssue.oneHand), lessThan(order.indexOf(CaptureIssue.outOfFrame)));
  });

  test('hand issues have default text and icons', () {
    const strings = MovementCaptureStrings();
    const icons = MovementCaptureIcons();
    expect(strings.issue(CaptureIssue.noHands), isNotEmpty);
    expect(strings.issue(CaptureIssue.oneHand), contains('one hand'));
    expect(icons.issue(CaptureIssue.noHands), isNot(icons.issue(CaptureIssue.oneHand)));
  });

  test('review mirroring matches what the live preview showed', () {
    final c = MovementCaptureConfig();
    // Android front: preview shown mirrored, file not, so flip the playback.
    expect(c.reviewMirrorFor(CameraKind.front, TargetPlatform.android), isTrue);
    // iOS front: preview and file both mirrored, so no flip.
    expect(c.reviewMirrorFor(CameraKind.front, TargetPlatform.iOS), isFalse);
    // USB: mirror view on, file not mirrored, so flip.
    expect(
        c.reviewMirrorFor(CameraKind.external, TargetPlatform.android), isTrue);
    // Back: nothing mirrored.
    expect(c.reviewMirrorFor(CameraKind.back, TargetPlatform.iOS), isFalse);
  });

  test('review before upload is on by default', () {
    expect(MovementCaptureConfig().reviewBeforeUpload, isTrue);
    expect(MovementCaptureConfig(reviewBeforeUpload: false).reviewBeforeUpload,
        isFalse);
  });
}
