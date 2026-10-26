import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/capture_step.dart';
import 'package:movement_capture/src/domain/capture_storage.dart';
import 'package:movement_capture/src/domain/uploader.dart';
import 'package:movement_capture/src/presentation/step_uploads.dart';

class _FakeStorage implements CaptureStorage {
  final List<String> deleted = [];

  @override
  Future<File> adopt(String rawPath) async => File(rawPath);

  @override
  Future<File> writeLandmarks(String json) async => File('landmarks.json');

  @override
  Future<void> deletePath(String path) async => deleted.add(path);

  @override
  Future<void> purgeAll() async {}
}

/// Completes each upload when the test says so.
class _ManualUploader implements MovementUploader {
  final List<MovementClip> started = [];
  final List<Completer<String>> _gates = [];
  final List<void Function(double)> _progress = [];

  @override
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  }) {
    started.add(clip);
    _progress.add(onProgress);
    final gate = Completer<String>();
    _gates.add(gate);
    return gate.future;
  }

  void succeed(int i, String id) => _gates[i].complete(id);
  void fail(int i) => _gates[i].completeError(Exception('network'));
  void report(int i, double p) => _progress[i](p);
}

MovementClip _clip(CaptureStep step, {bool landmarks = false}) => MovementClip(
      file: File('${step.name}.mp4'),
      landmarksFile: landmarks ? File('${step.name}.json') : null,
      duration: const Duration(seconds: 5),
      resolution: ResolutionPreset.high,
      capturedAtUtc: DateTime.utc(2026),
      metadata: const {},
      platform: 'android',
      cameraKind: 'external',
      fileMirrored: false,
      liveChecks: true,
      sessionId: 's',
      step: step,
      stepIndex: step.index,
      stepCount: 4,
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _ManualUploader uploader;
  late _FakeStorage storage;
  late int changes;
  late StepUploads uploads;

  setUp(() {
    uploader = _ManualUploader();
    storage = _FakeStorage();
    changes = 0;
    uploads = StepUploads(
      uploader: uploader,
      storage: storage,
      onChanged: () => changes++,
    );
  });

  test('uploads run one at a time, in the order they were queued', () async {
    uploads
      ..enqueue(_clip(CaptureStep.fullBody))
      ..enqueue(_clip(CaptureStep.face));
    await _settle();
    expect(uploader.started.map((c) => c.step), [CaptureStep.fullBody]);

    uploader.succeed(0, 'id-body');
    await _settle();
    expect(uploader.started.map((c) => c.step),
        [CaptureStep.fullBody, CaptureStep.face]);
    expect(uploads.hasPending, isTrue);

    uploader.succeed(1, 'id-face');
    await _settle();
    expect(uploads.hasPending, isFalse);
    expect(uploads.analysisIdFor(CaptureStep.fullBody), 'id-body');
    expect(uploads.analysisIdFor(CaptureStep.face), 'id-face');
    expect(uploads.analysisIdFor(CaptureStep.hands), isNull);
  });

  test('a finished upload deletes its video and landmarks files', () async {
    uploads.enqueue(_clip(CaptureStep.fullBody, landmarks: true));
    await _settle();
    uploader.succeed(0, 'id');
    await _settle();
    expect(storage.deleted, ['fullBody.mp4', 'fullBody.json']);
  });

  test('progress is the mean over all queued steps', () async {
    uploads
      ..enqueue(_clip(CaptureStep.fullBody))
      ..enqueue(_clip(CaptureStep.face));
    await _settle();
    uploader.report(0, 0.5);
    expect(uploads.progress, closeTo(0.25, 1e-9));
    uploader.report(0, 7); // clamped
    expect(uploads.progress, closeTo(0.5, 1e-9));
  });

  test('a failed upload keeps its files and can be retried', () async {
    uploads.enqueue(_clip(CaptureStep.fullBody));
    await _settle();
    uploader.fail(0);
    await _settle();
    expect(uploads.failedCount, 1);
    expect(uploads.hasPending, isFalse);
    expect(storage.deleted, isEmpty);

    uploads.retryFailed();
    await _settle();
    expect(uploads.failedCount, 0);
    expect(uploads.hasPending, isTrue);
    expect(uploader.started.length, 2);
    uploader.succeed(1, 'id');
    await _settle();
    expect(uploads.analysisIdFor(CaptureStep.fullBody), 'id');
  });

  test('an empty analysis id counts as a failure', () async {
    uploads.enqueue(_clip(CaptureStep.fullBody));
    await _settle();
    uploader.succeed(0, '');
    await _settle();
    expect(uploads.failedCount, 1);
    expect(uploads.analysisIdFor(CaptureStep.fullBody), isNull);
  });

  test('cancelAll stops later uploads and ignores late results', () async {
    uploads
      ..enqueue(_clip(CaptureStep.fullBody))
      ..enqueue(_clip(CaptureStep.face));
    await _settle();
    uploads.cancelAll();
    uploader.succeed(0, 'late');
    await _settle();
    expect(uploader.started.length, 1); // the queued face upload never began
    expect(uploads.analysisIdFor(CaptureStep.fullBody), isNull);
  });

  test('deleteAllFiles removes every queued clip', () async {
    uploads
      ..enqueue(_clip(CaptureStep.fullBody, landmarks: true))
      ..enqueue(_clip(CaptureStep.face));
    await uploads.deleteAllFiles();
    expect(storage.deleted,
        ['fullBody.mp4', 'fullBody.json', 'face.mp4']);
  });

  test('onChanged fires as uploads progress', () async {
    uploads.enqueue(_clip(CaptureStep.fullBody));
    await _settle();
    final before = changes;
    uploader.report(0, 0.3);
    expect(changes, greaterThan(before));
  });
}
