import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/camera_quality.dart';
import 'package:movement_capture/src/domain/config.dart';

void main() {
  final config = MovementCaptureConfig();

  test('good size and rate pass', () {
    expect(
        cameraIsGoodEnough(config: config, width: 1280, height: 720, fps: 30),
        isTrue);
  });

  test('low resolution fails, either orientation', () {
    expect(cameraIsGoodEnough(config: config, width: 320, height: 240, fps: 30),
        isFalse);
    expect(cameraIsGoodEnough(config: config, width: 240, height: 320, fps: 30),
        isFalse);
  });

  test('low frame rate fails', () {
    expect(cameraIsGoodEnough(config: config, width: 1280, height: 720, fps: 5),
        isFalse);
  });

  test('thresholds come from config', () {
    final strict = MovementCaptureConfig(minCameraShortSide: 2000);
    expect(
        cameraIsGoodEnough(config: strict, width: 1280, height: 720, fps: 30),
        isFalse);
    final lax = MovementCaptureConfig(minCameraFps: 1);
    expect(cameraIsGoodEnough(config: lax, width: 1280, height: 720, fps: 5),
        isTrue);
  });

  test('FrameRateMeter reports null until the window has passed', () {
    final t0 = DateTime(2026);
    final m = FrameRateMeter(const Duration(seconds: 2));
    expect(m.add(t0), isNull);
    expect(m.add(t0.add(const Duration(seconds: 1))), isNull);
    for (var i = 1; i <= 19; i++) {
      m.add(t0.add(Duration(milliseconds: 1000 + i * 50)));
    }
    final fps = m.add(t0.add(const Duration(seconds: 2)));
    expect(fps, closeTo(11, 1)); // 22 frames over 2 s
    expect(m.add(t0.add(const Duration(seconds: 3))), isNull); // reports once
  });
}
