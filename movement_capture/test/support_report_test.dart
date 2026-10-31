import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/native_support_info.dart';
import 'package:movement_capture/src/domain/support_report.dart';

CameraDescription _cam(String id, CameraLensDirection d) =>
    CameraDescription(name: id, lensDirection: d, sensorOrientation: 0);

final _goodCameras = [
  _cam('0', CameraLensDirection.back),
  _cam('1', CameraLensDirection.front),
  _cam('100', CameraLensDirection.external),
];

NativeSupportInfo _native({
  String platform = 'android',
  String os = '14',
  int? sdk = 34,
  bool declared = true,
  String auth = 'notDetermined',
  int free = 5000000000,
  int ram = 6000000000,
  bool lowRam = false,
  bool simulator = false,
}) =>
    NativeSupportInfo(
      platform: platform,
      osVersion: os,
      sdkInt: sdk,
      deviceModel: 'test',
      cameraPermissionDeclared: declared,
      cameraAuthorization: auth,
      hasCameraHardware: true,
      freeBytes: free,
      totalMemoryBytes: ram,
      isLowRamDevice: lowRam,
      isSimulator: simulator,
    );

void main() {
  test('healthy Android device can run and is ready', () {
    final r = evaluateSupport(
        platform: 'android',
        native: _native(),
        cameras: _goodCameras,
        mlKitAvailable: true);
    expect(r.canRun, isTrue);
    expect(r.readyNow, isTrue);
    expect(r.issues, isEmpty);
  });

  test('web and desktop are unsupported and nothing else is checked', () {
    final r = evaluateSupport(
        platform: 'web', native: null, cameras: null, mlKitAvailable: false);
    expect(r.canRun, isFalse);
    expect(r.issues.single.code, SupportIssueCode.unsupportedPlatform);
  });

  test('missing iOS camera description blocks (would crash)', () {
    final r = evaluateSupport(
        platform: 'ios',
        native:
            _native(platform: 'ios', os: '17.4', sdk: null, declared: false),
        cameras: _goodCameras,
        mlKitAvailable: true);
    expect(r.canRun, isFalse);
    expect(r.has(SupportIssueCode.cameraPermissionNotDeclared), isTrue);
  });

  test('iOS without native info blocks; Android only warns', () {
    final ios = evaluateSupport(
        platform: 'ios',
        native: null,
        cameras: _goodCameras,
        mlKitAvailable: true);
    expect(ios.canRun, isFalse);
    expect(ios.has(SupportIssueCode.checkFailed), isTrue);

    final android = evaluateSupport(
        platform: 'android',
        native: null,
        cameras: _goodCameras,
        mlKitAvailable: true);
    expect(android.canRun, isTrue);
    expect(android.has(SupportIssueCode.nativeInfoUnavailable), isTrue);
  });

  test('old OS versions block', () {
    expect(
        evaluateSupport(
                platform: 'ios',
                native: _native(platform: 'ios', os: '15.4.1', sdk: null),
                cameras: _goodCameras,
                mlKitAvailable: true)
            .has(SupportIssueCode.osTooOld),
        isTrue);
    expect(
        evaluateSupport(
                platform: 'ios',
                native: _native(platform: 'ios', os: '15.5', sdk: null),
                cameras: _goodCameras,
                mlKitAvailable: true)
            .has(SupportIssueCode.osTooOld),
        isFalse);
    expect(
        evaluateSupport(
                platform: 'android',
                native: _native(sdk: 23),
                cameras: _goodCameras,
                mlKitAvailable: true)
            .canRun,
        isFalse);
  });

  test('denied access is user-fixable; restricted blocks', () {
    final denied = evaluateSupport(
        platform: 'ios',
        native: _native(platform: 'ios', os: '17.0', sdk: null, auth: 'denied'),
        cameras: _goodCameras,
        mlKitAvailable: true);
    expect(denied.canRun, isTrue);
    expect(denied.readyNow, isFalse);

    final restricted = evaluateSupport(
        platform: 'ios',
        native:
            _native(platform: 'ios', os: '17.0', sdk: null, auth: 'restricted'),
        cameras: _goodCameras,
        mlKitAvailable: true);
    expect(restricted.canRun, isFalse);
  });

  test('no cameras or failed listing blocks', () {
    expect(
        evaluateSupport(
                platform: 'android',
                native: _native(),
                cameras: const [],
                mlKitAvailable: true)
            .has(SupportIssueCode.noCamera),
        isTrue);
    expect(
        evaluateSupport(
                platform: 'android',
                native: _native(),
                cameras: null,
                mlKitAvailable: true)
            .canRun,
        isFalse);
  });

  test('ML Kit failure blocks', () {
    final r = evaluateSupport(
        platform: 'android',
        native: _native(),
        cameras: _goodCameras,
        mlKitAvailable: false,
        mlKitError: 'MissingPluginException');
    expect(r.canRun, isFalse);
    expect(r.has(SupportIssueCode.mlKitUnavailable), isTrue);
  });

  test('low storage is user-fixable; low memory and no USB camera only warn',
      () {
    final r = evaluateSupport(
        platform: 'android',
        native: _native(free: 50 * 1024 * 1024, ram: 2000000000),
        cameras: [_cam('1', CameraLensDirection.front)],
        mlKitAvailable: true);
    expect(r.canRun, isTrue);
    expect(r.readyNow, isFalse);
    expect(r.has(SupportIssueCode.lowStorage), isTrue);
    expect(r.has(SupportIssueCode.lowMemoryDevice), isTrue);
    expect(r.has(SupportIssueCode.noUsbCamera), isTrue);
  });

  test('requireUsbCamera turns a missing USB camera into a blocker', () {
    final r = evaluateSupport(
        platform: 'android',
        native: _native(),
        cameras: [_cam('1', CameraLensDirection.front)],
        mlKitAvailable: true,
        requirements: const SupportRequirements(requireUsbCamera: true));
    expect(r.canRun, isFalse);
  });

  test('describe() and toJson() never throw', () {
    final r = evaluateSupport(
        platform: 'android',
        native: null,
        cameras: null,
        mlKitAvailable: false);
    expect(r.describe(), contains('canRun=false'));
    expect(r.toJson()['issues'], isA<List<Object?>>());
  });

  test('hand tracking unavailable only warns', () {
    final r = evaluateSupport(
        platform: 'android',
        native: _native(),
        cameras: _goodCameras,
        mlKitAvailable: true,
        handTrackingAvailable: false);
    expect(r.canRun, isTrue);
    expect(r.readyNow, isTrue);
    expect(r.has(SupportIssueCode.handTrackingUnavailable), isTrue);
  });
}
