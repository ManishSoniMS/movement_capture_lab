import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

MovementClip _clip({Map<String, String> metadata = const {}}) => MovementClip(
      file: File('x.mp4'),
      duration: const Duration(seconds: 5),
      resolution: ResolutionPreset.high,
      capturedAtUtc: DateTime.utc(2026),
      metadata: metadata,
      platform: 'ios',
      cameraKind: 'front',
      fileMirrored: true,
      liveChecks: false,
      sessionId: 'abc123',
      step: CaptureStep.face,
      stepIndex: 1,
      stepCount: 4,
    );

void main() {
  test('formFields carry the device and step fields as strings', () {
    expect(_clip().formFields, {
      'durationMs': '5000',
      'resolutionPreset': 'high',
      'capturedAt': '2026-01-01T00:00:00.000Z',
      'platform': 'ios',
      'cameraKind': 'front',
      'fileMirrored': 'true',
      'liveChecks': 'false',
      'sessionId': 'abc123',
      'step': 'face',
      'stepIndex': '1',
      'stepCount': '4',
    });
  });

  test('metadata comes first and the package fields win a name clash', () {
    final fields = _clip(metadata: {
      'chatSessionId': 'chat-1',
      'step': 'spoofed',
    }).formFields;
    expect(fields['chatSessionId'], 'chat-1');
    expect(fields['step'], 'face');
  });

  test('landmarksFile is optional', () {
    expect(_clip().landmarksFile, isNull);
  });
}
