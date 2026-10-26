import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/capture_state.dart';

CameraDescription _cam(String id, CameraLensDirection d) =>
    CameraDescription(name: id, lensDirection: d, sensorOrientation: 0);

void main() {
  final back = _cam('0', CameraLensDirection.back);
  final front = _cam('1', CameraLensDirection.front);
  final usbA = _cam('100', CameraLensDirection.external);
  final usbB = _cam('101', CameraLensDirection.external);

  test('orders USB cameras first, then front, then back', () {
    final choices = buildCameraChoices([back, usbA, front, usbB]);
    expect(choices.map((c) => c.id), ['100', '101', '1', '0']);
    expect(choices.first.ordinal, 1);
    expect(choices.first.countOfKind, 2);
  });

  test('defaults to the first USB camera when one is connected', () {
    final choices = buildCameraChoices([back, front, usbA]);
    expect(pickDefaultCamera(choices)?.id, '100');
  });

  test('falls back to the front camera when no USB camera is connected', () {
    final choices = buildCameraChoices([back, front]);
    expect(pickDefaultCamera(choices)?.id, '1');
  });

  test('falls back to the back camera when there is no front camera', () {
    expect(pickDefaultCamera(buildCameraChoices([back]))?.id, '0');
  });

  test('uses the preferred camera when it is still connected', () {
    final choices = buildCameraChoices([back, front, usbA]);
    expect(pickDefaultCamera(choices, preferredId: '1')?.id, '1');
  });

  test('ignores a preferred camera that has been unplugged', () {
    final choices = buildCameraChoices([back, front]);
    expect(pickDefaultCamera(choices, preferredId: '100')?.id, '1');
  });

  test('returns null when there are no cameras', () {
    expect(pickDefaultCamera(const []), isNull);
  });

  test('labels number cameras only when there is more than one of a kind', () {
    const strings = MovementCaptureStrings();
    final one = buildCameraChoices([usbA, front]);
    expect(strings.cameraLabel(one[0]), 'USB camera');
    expect(strings.cameraLabel(one[1]), 'Tablet front camera');
    final two = buildCameraChoices([usbA, usbB]);
    expect(strings.cameraLabel(two[1]), 'USB camera 2');
  });

  group('analysisRotationDegrees', () {
    test('iOS needs no rotation: the plugin already turns the frames', () {
      for (final kind in CameraKind.values) {
        expect(
          analysisRotationDegrees(
              kind: kind,
              sensorOrientation: 90,
              screenDegrees: 270,
              isIOS: true),
          0,
        );
      }
    });

    test('an explicit override wins on every platform and camera', () {
      expect(
        analysisRotationDegrees(
            kind: CameraKind.external,
            sensorOrientation: 0,
            screenDegrees: 270,
            configRotation: 180),
        180,
      );
      expect(
        analysisRotationDegrees(
            kind: CameraKind.front,
            sensorOrientation: 270,
            screenDegrees: 90,
            configRotation: 90,
            isIOS: true),
        90,
      );
    });

    test('USB camera follows the back-camera rule', () {
      expect(
        analysisRotationDegrees(
            kind: CameraKind.external,
            sensorOrientation: 0,
            screenDegrees: 270),
        90, // (0 - 270 + 360) % 360
      );
      expect(
        analysisRotationDegrees(
            kind: CameraKind.external, sensorOrientation: 0, screenDegrees: 90),
        270,
      );
    });

    test('front camera adds screen rotation to sensor orientation', () {
      expect(
        analysisRotationDegrees(
            kind: CameraKind.front, sensorOrientation: 270, screenDegrees: 90),
        0, // (270 + 90) % 360
      );
    });

    test('back camera subtracts screen rotation from sensor orientation', () {
      expect(
        analysisRotationDegrees(
            kind: CameraKind.back, sensorOrientation: 90, screenDegrees: 270),
        180, // (90 - 270 + 360) % 360
      );
    });
  });

  test('CameraFailure.noCamera maps to the no-camera message', () {
    const strings = MovementCaptureStrings();
    expect(strings.cameraFailure(CameraFailure.noCamera), strings.cameraNone);
  });
}
