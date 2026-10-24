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
}
