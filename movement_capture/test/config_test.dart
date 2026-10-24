import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

void main() {
  test('maxDuration is clamped to 5–30 s', () {
    expect(MovementCaptureConfig(maxDuration: const Duration(seconds: 45)).maxDuration,
        const Duration(seconds: 30));
    expect(MovementCaptureConfig(maxDuration: const Duration(seconds: 2)).maxDuration,
        const Duration(seconds: 5));
    expect(MovementCaptureConfig(maxDuration: const Duration(seconds: 12)).maxDuration,
        const Duration(seconds: 12));
  });

  test('rejects an invalid rotation', () {
    expect(() => MovementCaptureConfig(cameraRotationDegrees: 45),
        throwsA(isA<AssertionError>()));
  });
}
