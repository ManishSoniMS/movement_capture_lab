import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/capture_state.dart';
import 'package:movement_capture/src/domain/usb_video_device.dart';

CameraDescription _cam(String id, CameraLensDirection d) =>
    CameraDescription(name: id, lensDirection: d, sensorOrientation: 0);

void main() {
  usbDirectTests();
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

  test('uses the preferred camera when no USB camera is connected', () {
    final choices = buildCameraChoices([back, front]);
    expect(pickDefaultCamera(choices, preferredId: '0')?.id, '0');
  });

  group('USB camera wins over a saved tablet camera', () {
    test('saved tablet id + USB connected -> USB', () {
      final choices = buildCameraChoices([back, front, usbA]);
      expect(pickDefaultCamera(choices, preferredId: '1')?.id, '100');
      expect(pickDefaultCamera(choices, preferredId: '0')?.id, '100');
    });

    test('saved USB id still present -> that one', () {
      final choices = buildCameraChoices([back, front, usbA, usbB]);
      expect(pickDefaultCamera(choices, preferredId: '101')?.id, '101');
    });

    test('saved USB id gone, another USB present -> the other USB', () {
      final choices = buildCameraChoices([back, front, usbB]);
      expect(pickDefaultCamera(choices, preferredId: '100')?.id, '101');
    });

    test('camera chosen this session is kept, even a tablet camera', () {
      final choices = buildCameraChoices([back, front, usbA]);
      expect(pickDefaultCamera(choices, sessionChoiceId: '1')?.id, '1');
      expect(
        pickDefaultCamera(choices, sessionChoiceId: '1', preferredId: '100')
            ?.id,
        '1',
      );
    });

    test('session choice that is gone falls through to the USB rule', () {
      final choices = buildCameraChoices([back, front, usbA]);
      expect(pickDefaultCamera(choices, sessionChoiceId: '9')?.id, '100');
    });

    test('no USB: saved id, then front, then back', () {
      final choices = buildCameraChoices([back, front]);
      expect(pickDefaultCamera(choices, preferredId: '0')?.id, '0');
      expect(pickDefaultCamera(choices, preferredId: '9')?.id, '1');
      expect(pickDefaultCamera(buildCameraChoices([back]))?.id, '0');
    });
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

// ---- direct USB (R16)
void usbDirectTests() {
  CameraDescription cam(String id, CameraLensDirection d) =>
      CameraDescription(name: id, lensDirection: d, sensorOrientation: 0);
  const arducam = UsbVideoDevice(
    deviceName: '/dev/bus/usb/002/005',
    vendorId: 0x0c45,
    productId: 0x0261,
    productName: 'Arducam 1080P Low Light',
  );
  final back = cam('0', CameraLensDirection.back);
  final front = cam('1', CameraLensDirection.front);
  final usbPlugin = cam('100', CameraLensDirection.external);

  group('direct USB', () {
    test('listed first as external when the plugin has no external camera',
        () {
      final c = buildCameraChoices([back, front], [arducam]);
      expect(c.map((e) => e.id), ['usb:0c45:0261', '1', '0']);
      expect(c.first.isExternal, isTrue);
      expect(c.first.isUsbDirect, isTrue);
      expect(c.first.description, isNull);
      expect(c.first.label, 'Arducam 1080P Low Light');
      expect(c.first.usbDeviceName, '/dev/bus/usb/002/005');
    });

    test('ignored when the plugin already lists an external camera', () {
      final c = buildCameraChoices([back, front, usbPlugin], [arducam]);
      expect(c.map((e) => e.id), ['100', '1', '0']);
      expect(c.any((e) => e.isUsbDirect), isFalse);
    });

    test('id is zero-padded hex and stable across replugs', () {
      const moved = UsbVideoDevice(
        deviceName: '/dev/bus/usb/001/009',
        vendorId: 0x1,
        productId: 0x2,
        productName: 'x',
      );
      expect(buildCameraChoices([], [moved]).first.id, 'usb:0001:0002');
      final a = buildCameraChoices([back], [arducam]).first.id;
      const replug = UsbVideoDevice(
        deviceName: '/dev/bus/usb/002/017',
        vendorId: 0x0c45,
        productId: 0x0261,
        productName: 'Arducam 1080P Low Light',
      );
      expect(buildCameraChoices([back], [replug]).first.id, a);
    });

    test('pickDefaultCamera: saved usb id present or absent', () {
      final withUsb = buildCameraChoices([back, front], [arducam]);
      expect(pickDefaultCamera(withUsb, preferredId: 'usb:0c45:0261')?.id,
          'usb:0c45:0261');
      expect(pickDefaultCamera(withUsb, preferredId: '1')?.id, 'usb:0c45:0261');
      final noUsb = buildCameraChoices([back, front]);
      expect(pickDefaultCamera(noUsb, preferredId: 'usb:0c45:0261')?.id, '1');
    });

    test('numbering counts direct USB cameras', () {
      const second = UsbVideoDevice(
        deviceName: '/dev/bus/usb/002/006',
        vendorId: 0x1,
        productId: 0x1,
        productName: 'B',
      );
      final c = buildCameraChoices([], [arducam, second]);
      expect(c.map((e) => e.ordinal), [1, 2]);
      expect(c.first.countOfKind, 2);
    });

    test('UsbVideoDevice.fromMap parses the native map', () {
      final d = UsbVideoDevice.fromMap({
        'deviceName': '/dev/bus/usb/002/005',
        'vendorId': 3141,
        'productId': 609,
        'productName': 'Arducam',
        'hasPermission': true,
        'maxPowerMa': 500,
      });
      expect(d.vendorId, 0x0c45);
      expect(d.hasPermission, isTrue);
      expect(d.maxPowerMa, 500);
    });
  });
}
