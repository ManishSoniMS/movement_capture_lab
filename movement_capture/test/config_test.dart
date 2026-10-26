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

  test('mirroring defaults differ by platform for the front camera', () {
    final c = MovementCaptureConfig();
    expect(
        c.mirrorPreviewFor(CameraKind.front, TargetPlatform.android), isTrue);
    expect(c.mirrorPreviewFor(CameraKind.front, TargetPlatform.iOS), isFalse);
    expect(c.mirrorPreviewFor(CameraKind.external, TargetPlatform.iOS), isTrue);
    expect(
        c.mirrorPreviewFor(CameraKind.back, TargetPlatform.android), isFalse);
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
}
