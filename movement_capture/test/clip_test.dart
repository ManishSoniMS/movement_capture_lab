import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

MovementClip _clip({
  Map<String, String> metadata = const {},
  SideChoice sideChoice = SideChoice.both,
}) =>
    MovementClip(
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
      sideChoice: sideChoice,
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
      'retakes': '0',
      'reviewed': 'false',
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

  test('retakes and reviewed are sent when set', () {
    final clip = MovementClip(
      file: File('x.mp4'),
      duration: const Duration(seconds: 5),
      resolution: ResolutionPreset.high,
      capturedAtUtc: DateTime.utc(2026),
      metadata: const {},
      platform: 'ios',
      cameraKind: 'front',
      fileMirrored: false,
      liveChecks: true,
      sessionId: 'abc123',
      step: CaptureStep.face,
      stepIndex: 1,
      stepCount: 4,
      retakes: 2,
      reviewed: true,
    );
    expect(clip.formFields['retakes'], '2');
    expect(clip.formFields['reviewed'], 'true');
  });

  test('landmarksFile is optional', () {
    expect(_clip().landmarksFile, isNull);
  });

  test('sides is sent for one-sided scans only', () {
    expect(_clip().formFields.containsKey('sides'), isFalse);
    expect(_clip(sideChoice: SideChoice.leftOnly).formFields['sides'], 'left');
    expect(
        _clip(sideChoice: SideChoice.rightOnly).formFields['sides'], 'right');
  });
}
