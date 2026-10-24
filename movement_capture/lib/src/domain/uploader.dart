import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';

/// A finished recording handed to the uploader. The package deletes [file]
/// after a successful upload; the uploader must not keep a reference to it.
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

  /// The four fields above as strings, ready for a multipart form.
  Map<String, String> get deviceFields => {
        'platform': platform,
        'cameraKind': cameraKind,
        'fileMirrored': '$fileMirrored',
        'liveChecks': '$liveChecks',
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
abstract interface class MovementUploader {
  /// Uploads [clip] and returns a non-empty analysis id.
  ///
  /// Report progress as 0.0–1.0. Throw any error on failure; the package
  /// shows a Retry button. Retry policy (attempts, backoff) is the uploader's
  /// job. When [cancellation] fires, stop as soon as possible; anything
  /// returned or thrown afterwards is ignored.
  Future<String> upload(
    MovementClip clip, {
    required void Function(double progress) onProgress,
    required UploadCancellation cancellation,
  });
}
