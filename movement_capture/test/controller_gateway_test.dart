import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/data/usb_direct_camera_gateway.dart'
    show nv21CameraImage;
import 'package:movement_capture/src/domain/camera_catalog.dart';
import 'package:movement_capture/src/domain/camera_choice.dart';
import 'package:movement_capture/src/domain/camera_gateway.dart';
import 'package:movement_capture/src/domain/capture_state.dart';
import 'package:movement_capture/src/domain/capture_storage.dart';
import 'package:movement_capture/src/domain/capture_step.dart';
import 'package:movement_capture/src/domain/frame_analyzer.dart';
import 'package:movement_capture/src/domain/frame_metrics.dart';
import 'package:movement_capture/src/domain/luma_stats.dart';
import 'package:movement_capture/src/domain/usb_video_device.dart';
import 'package:movement_capture/src/presentation/controller.dart';

class FakeGateway implements CameraGateway {
  FakeGateway(this.choice, {this.failInit = false});
  final CameraChoice choice;
  final bool failInit;
  final _lost = StreamController<CameraLost>.broadcast();
  void Function(CameraImage)? onFrame;
  bool initialized = false;
  bool streaming = false;
  bool recording = false;
  bool disposed = false;
  String? path;

  @override
  Future<void> initialize() async {
    if (failInit) throw const CameraGatewayException('boom', code: 'x');
    initialized = true;
  }

  @override
  CameraFrameSize get frameSize => const CameraFrameSize(1280, 720);
  @override
  int get sensorOrientation => 0;
  @override
  int get previewOrientationDegrees => 0;
  @override
  bool get isInitialized => initialized;
  @override
  bool get isStreaming => streaming;
  @override
  bool get isRecording => recording;
  @override
  String? get activeRecordingPath => recording ? path : null;

  @override
  Future<void> startImageStream(void Function(CameraImage) f) async {
    onFrame = f;
    streaming = true;
  }

  @override
  Future<void> stopImageStream() async {
    streaming = false;
  }

  @override
  Future<void> startRecording({void Function(CameraImage)? onFrame}) async {
    this.onFrame = onFrame;
    path = '${Directory.systemTemp.path}/fake_${identityHashCode(this)}.mp4';
    File(path!).writeAsBytesSync([1, 2, 3]);
    recording = true;
  }

  @override
  Future<String> stopRecording() async {
    recording = false;
    return path!;
  }

  @override
  Stream<CameraLost> get lost => _lost.stream;

  void lose(CameraLostReason r) => _lost.add(CameraLost(r));

  void frame() => onFrame?.call(nv21CameraImage(Uint8List(6), 2, 2));

  @override
  Future<void> dispose() async {
    disposed = true;
    streaming = false;
    await _lost.close();
  }
}

class FakeCatalog implements CameraCatalog {
  FakeCatalog(this.choices);
  List<CameraChoice> choices;
  bool permission = true;
  UsbPermissionResult result = UsbPermissionResult.granted;
  int requests = 0;

  @override
  Future<List<CameraChoice>> list() async => choices;
  @override
  Future<bool> hasUsbPermission(CameraChoice c) async =>
      !c.isUsbDirect || permission;
  @override
  Future<UsbPermissionResult> requestUsbPermission(CameraChoice c) async {
    requests++;
    if (result == UsbPermissionResult.granted) permission = true;
    return result;
  }
}

class FakeStorage implements CaptureStorage {
  final deleted = <String>[];
  @override
  Future<File> adopt(String rawPath) async => File(rawPath);
  @override
  Future<File> writeLandmarks(String json) async => File('l.json');
  @override
  Future<void> deletePath(String p) async {
    deleted.add(p);
    try {
      File(p).deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> purgeAll() async {}
}

class GoodAnalyzer implements FrameAnalyzer {
  @override
  CaptureStep get step => CaptureStep.fullBody;
  @override
  Future<FrameCheck?> analyze(CameraImage image) async => FrameCheck(
        issues: const {},
        at: DateTime.now(),
        metrics: const FrameMetrics(
          step: CaptureStep.fullBody,
          luma: LumaStats(mean: 128, clippedFraction: 0, centerToBorder: 1),
          faces: 0,
          poses: 1,
          landmarks: [],
          issues: {},
          analysesPerSecond: 5,
          rotationDegrees: 0,
        ),
      );
  @override
  Future<void> close() async {}
}

class NoUploader implements MovementUploader {
  @override
  Future<String> upload(MovementClip clip,
          {required void Function(double progress) onProgress,
          required UploadCancellation cancellation}) async =>
      'id';
}

CameraDescription _desc(String id, CameraLensDirection d) =>
    CameraDescription(name: id, lensDirection: d, sensorOrientation: 90);

const _arducam = UsbVideoDevice(
  deviceName: '/dev/bus/usb/002/005',
  vendorId: 0x0c45,
  productId: 0x0261,
  productName: 'Arducam 1080P Low Light',
);

void main() {
  late FakeCatalog catalog;
  late FakeStorage storage;
  late List<FakeGateway> gateways;
  late MovementCaptureController c;
  late CameraChoice usb, front, back;
  final picks = <String>[];

  setUp(() {
    final choices = buildCameraChoices([
      _desc('0', CameraLensDirection.back),
      _desc('1', CameraLensDirection.front),
    ], [
      _arducam
    ]);
    usb = choices.first;
    front = choices[1];
    back = choices[2];
    catalog = FakeCatalog(choices);
    storage = FakeStorage();
    gateways = [];
    picks.clear();
  });

  MovementCaptureController make({bool failUsbInit = false}) =>
      c = MovementCaptureController(
        config: MovementCaptureConfig(
          steps: [CaptureStep.fullBody],
          maxDuration: const Duration(seconds: 5),
          countdown: const Duration(seconds: 1),
          stableBeforeStart: Duration.zero,
          violationGrace: Duration.zero,
        ),
        uploader: NoUploader(),
        storage: storage,
        catalog: catalog,
        analyzerFactory: (cfg,
                {required step,
                required rotationDegrees,
                required interval,
                sideChoice,
                framesMirrored}) =>
            GoodAnalyzer(),
        gatewayFactory: (choice) {
          final g = FakeGateway(choice, failInit: false);
          gateways.add(g);
          return g;
        },
        onCameraIdChanged: picks.add,
      );

  Future<void> until(bool Function() ok, {int ms = 4000}) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('timeout; state=${c.state}');
      for (final g in gateways) {
        g.frame();
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  tearDown(() async {
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('opens USB first, checks, countdown, recording, review', () async {
    make();
    await c.start();
    expect(c.selectedCamera?.id, 'usb:0c45:0261');
    expect(c.state, isA<Checking>());
    expect(gateways.single.streaming, isTrue);
    c.startRequested();
    await until(() => c.state is CountingDown);
    await until(() => c.state is Recording);
    expect(gateways.single.recording, isTrue);
    await until(() => c.state is Reviewing, ms: 8000);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('camera lost while checking falls back to the built-in camera',
      () async {
    make();
    await c.start();
    gateways.first.lose(CameraLostReason.unplugged);
    await until(() => gateways.length == 2 && c.state is Checking);
    expect(c.selectedCamera?.id, '1');
    expect(c.usbFallbackActive, isTrue);
    expect(gateways.first.disposed, isTrue);
    expect(picks, isEmpty); // automatic fallback is not an operator pick
  });

  test('camera lost while recording deletes the partial file, falls back',
      () async {
    make();
    await c.start();
    c.startRequested();
    await until(() => c.state is Recording);
    final path = gateways.first.path!;
    gateways.first.lose(CameraLostReason.error);
    await until(() => gateways.length == 2 && c.state is Checking);
    expect(storage.deleted, contains(path));
    expect(File(path).existsSync(), isFalse);
    expect(c.selectedCamera?.id, '1');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('noFrames falls back to the built-in camera', () async {
    make();
    await c.start();
    gateways.first.lose(CameraLostReason.noFrames);
    await until(() => gateways.length == 2 && c.state is Checking);
    expect(c.selectedCamera?.isUsbDirect, isFalse);
  });

  test('dispose while recording deletes the file', () async {
    make();
    await c.start();
    c.startRequested();
    await until(() => c.state is Recording);
    final path = gateways.first.path!;
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(path).existsSync(), isFalse);
    expect(gateways.first.disposed, isTrue);
    c = make(); // so tearDown has something to dispose
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('USB permission needed -> panel -> granted -> opens', () async {
    catalog.permission = false;
    make();
    await c.start();
    expect(c.state, isA<CameraUnavailable>());
    expect((c.state as CameraUnavailable).reason,
        CameraFailure.usbPermissionNeeded);
    expect(gateways, isEmpty);
    await c.requestUsbPermission();
    expect(catalog.requests, 1);
    expect(c.state, isA<Checking>());
    expect(c.selectedCamera?.id, 'usb:0c45:0261');
  });

  test('USB permission denied -> built-in camera with notice', () async {
    catalog.permission = false;
    catalog.result = UsbPermissionResult.denied;
    make();
    await c.start();
    await c.requestUsbPermission();
    expect(c.state, isA<Checking>());
    expect(c.selectedCamera?.id, '1');
    expect(c.usbFallbackActive, isTrue);
  });

  test('operator picks the direct-USB camera in the chooser', () async {
    make();
    await c.start();
    await c.selectCamera(front);
    expect(c.selectedCamera?.id, '1');
    expect(c.usbFallbackActive, isFalse);
    await c.selectCamera(usb);
    expect(c.selectedCamera?.id, 'usb:0c45:0261');
    expect(picks, ['1', 'usb:0c45:0261']);
    expect(back.id, '0');
  });
}
