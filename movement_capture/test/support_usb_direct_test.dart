import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/native_support_info.dart';
import 'package:movement_capture/src/domain/support_report.dart';
import 'package:movement_capture/src/domain/usb_video_device.dart';

CameraDescription _cam(String id, CameraLensDirection d) =>
    CameraDescription(name: id, lensDirection: d, sensorOrientation: 0);

final _builtIn = [
  _cam('0', CameraLensDirection.back),
  _cam('1', CameraLensDirection.front),
];

const _native = NativeSupportInfo(
  platform: 'android',
  osVersion: '14',
  sdkInt: 34,
  cameraPermissionDeclared: true,
  cameraAuthorization: 'notDetermined',
  hasCameraHardware: true,
  freeBytes: 5000000000,
  totalMemoryBytes: 6000000000,
);

UsbVideoDevice _dev({bool permission = true}) => UsbVideoDevice(
      deviceName: '/dev/bus/usb/002/005',
      vendorId: 0x0c45,
      productId: 0x0261,
      productName: 'Arducam',
      hasPermission: permission,
    );

SupportReport _eval({
  List<UsbVideoDevice> devices = const [],
  bool available = true,
  UsbProbeResult probe = UsbProbeResult.notRun,
  List<CameraDescription>? cameras,
  bool requireUsb = false,
}) =>
    evaluateSupport(
      platform: 'android',
      native: _native,
      cameras: cameras ?? _builtIn,
      mlKitAvailable: true,
      usbVideoDevices: devices,
      usbDirectAvailable: available,
      usbProbe: probe,
      requirements: SupportRequirements(requireUsbCamera: requireUsb),
    );

void main() {
  test('no video device anywhere -> noUsbCamera', () {
    expect(_eval().has(SupportIssueCode.noUsbCamera), isTrue);
  });

  test('video device Camera2 lacks -> usbDirectInUse, not noUsbCamera', () {
    final r = _eval(devices: [_dev()]);
    expect(r.has(SupportIssueCode.noUsbCamera), isFalse);
    final i = r.issues.singleWhere((i) => i.code == SupportIssueCode.usbDirectInUse);
    expect(i.severity, SupportSeverity.warning);
    expect(r.canRun, isTrue);
    expect(r.readyNow, isTrue);
  });

  test('Camera2 lists the webcam -> no direct-USB issue', () {
    final r = _eval(
      devices: [_dev()],
      cameras: [..._builtIn, _cam('100', CameraLensDirection.external)],
    );
    expect(r.has(SupportIssueCode.usbDirectInUse), isFalse);
    expect(r.has(SupportIssueCode.noUsbCamera), isFalse);
  });

  test('no permission -> usbPermissionNeeded (userFixable), still canRun', () {
    final r = _eval(devices: [_dev(permission: false)]);
    final i = r.issues
        .singleWhere((i) => i.code == SupportIssueCode.usbPermissionNeeded);
    expect(i.severity, SupportSeverity.userFixable);
    expect(r.canRun, isTrue);
    expect(r.readyNow, isFalse);
  });

  test('native library missing -> usbDirectUnavailable warning', () {
    final r = _eval(devices: [_dev()], available: false);
    expect(r.has(SupportIssueCode.usbDirectInUse), isFalse);
    final i = r.issues
        .singleWhere((i) => i.code == SupportIssueCode.usbDirectUnavailable);
    expect(i.severity, SupportSeverity.warning);
    expect(r.canRun, isTrue);
  });

  test('library missing + requireUsbCamera blocks', () {
    final r = _eval(devices: [_dev()], available: false, requireUsb: true);
    expect(r.canRun, isFalse);
  });

  test('probe: no frames -> usbNoFrames warning', () {
    final r = _eval(devices: [_dev()], probe: UsbProbeResult.noFrames);
    expect(r.issues.singleWhere((i) => i.code == SupportIssueCode.usbNoFrames).severity,
        SupportSeverity.warning);
    expect(r.canRun, isTrue);
  });

  test('probe: open failed -> usbDirectUnavailable warning', () {
    final r = _eval(devices: [_dev()], probe: UsbProbeResult.failed);
    expect(r.has(SupportIssueCode.usbDirectUnavailable), isTrue);
  });

  test('probe ok or not run adds nothing', () {
    expect(_eval(devices: [_dev()], probe: UsbProbeResult.ok)
        .has(SupportIssueCode.usbNoFrames), isFalse);
    expect(_eval(devices: [_dev()]).has(SupportIssueCode.usbNoFrames), isFalse);
  });

  test('report text has the usb line', () {
    final r = _eval(devices: [_dev(permission: false)]);
    expect(r.toString(), contains('usb video devices: 1 · direct: yes · permission: no'));
    expect(r.usbVideoDevices, hasLength(1));
  });
}
