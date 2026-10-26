import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';

import 'capture_step.dart';

/// One recorded step handed to the uploader. The package deletes [file] and
/// [landmarksFile] after a successful upload; don't keep references to them.
class MovementClip {
  const MovementClip({
    required this.file,
    required this.duration,
    required this.resolution,
    required this.capturedAtUtc,
    required this.metadata,
    required this.platform,
    required this.cameraKind,
    required this.fileMirrored,
    required this.liveChecks,
    required this.sessionId,
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    this.landmarksFile,
  });

  final File file;
  final Duration duration;
  final ResolutionPreset resolution;
  final DateTime capturedAtUtc;

  /// Copied from MovementCaptureConfig.metadata (e.g. chatSessionId).
  final Map<String, String> metadata;

  /// "android" or "ios".
  final String platform;

  /// "external", "front" or "back".
  final String cameraKind;

  /// True when the video file itself is mirrored (iOS front camera).
  final bool fileMirrored;

  /// False when the recording ran without live quality checks.
  final bool liveChecks;

  /// Same for every step of one capture session.
  final String sessionId;
  final CaptureStep step;

  /// 0-based position in the session, and the number of configured steps.
  final int stepIndex;
  final int stepCount;

  /// landmarks.json (fullBody and face steps), or null.
  final File? landmarksFile;

  /// Every text field for a multipart form: metadata first, then the
  /// package's fields (which win on a name clash).
  Map<String, String> get formFields => {
        ...metadata,
        'durationMs': '${duration.inMilliseconds}',
        'resolutionPreset': resolution.name,
        'capturedAt': capturedAtUtc.toIso8601String(),
        'platform': platform,
        'cameraKind': cameraKind,
        'fileMirrored': '$fileMirrored',
        'liveChecks': '$liveChecks',
        'sessionId': sessionId,
        'step': step.name,
        'stepIndex': '$stepIndex',
        'stepCount': '$stepCount',
      };
}

/// Fired when the screen closes during an upload.
class UploadCancellation {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Implemented by the host app (and by the lab app for testing).
/// Called once per recorded step, one call at a time.
abstract interface class MovementUploader {
  /// Uploads [clip] and returns a non-empty analysis id.
  ///
  /// Report progress as 0.0–1.0. Throw any error on failure; the package
  /// offers a Retry. Retry policy (attempts, backoff) is the uploader's
  /// job. When [cancellation] fires, stop as soon as possible; anything
  /// returned or thrown afterwards is ignored.
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  });
}
