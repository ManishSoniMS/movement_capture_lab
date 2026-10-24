import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

void main() {
  test('deviceFields are the four multipart strings', () {
    final clip = MovementClip(
      file: File('x.mp4'),
      duration: const Duration(seconds: 5),
      resolution: ResolutionPreset.high,
      capturedAtUtc: DateTime.utc(2026),
      metadata: const {},
      platform: 'ios',
      cameraKind: 'front',
      fileMirrored: true,
      liveChecks: false,
    );
    expect(clip.deviceFields, {
      'platform': 'ios',
      'cameraKind': 'front',
      'fileMirrored': 'true',
      'liveChecks': 'false',
    });
  });
}
