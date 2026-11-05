import 'dart:ui' show Size;

import 'package:camera/camera.dart' show CameraImage;

import 'camera_choice.dart';

/// Pixel size of the frames the analyzer receives and of the recording.
class CameraFrameSize {
  const CameraFrameSize(this.width, this.height);
  final int width;
  final int height;

  int get shortSide => width < height ? width : height;
  Size toSize() => Size(width.toDouble(), height.toDouble());

  @override
  bool operator ==(Object other) =>
      other is CameraFrameSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

enum CameraLostReason { unplugged, error, noFrames }

/// The camera went away while open.
class CameraLost {
  const CameraLost(this.reason, [this.message = '']);
  final CameraLostReason reason;
  final String message;

  @override
  String toString() => 'CameraLost($reason, $message)';
}

/// Any failure of a [CameraGateway] call (open, stream, record). The
/// controller maps it to a user-facing [CameraFailure].
class CameraGatewayException implements Exception {
  const CameraGatewayException(
    this.message, {
    this.code = '',
    this.permissionDenied = false,
  });
  final String message;
  final String code;

  /// True when the camera permission is missing.
  final bool permissionDenied;

  @override
  String toString() => 'CameraGatewayException($code: $message)';
}

/// One opened camera, whatever drives it (the `camera` plugin or direct USB).
abstract interface class CameraGateway {
  Future<void> initialize();

  /// Size of the frames the analyzer receives and of the recording.
  CameraFrameSize get frameSize;

  /// For `analysisRotationDegrees`. Direct USB reports 0.
  int get sensorOrientation;

  /// Degrees the screen rotates the preview (0/90/180/270), for the analyzer.
  int get previewOrientationDegrees;

  /// True once [initialize] completed and the camera can be shown.
  bool get isInitialized;

  bool get isStreaming;
  bool get isRecording;

  /// Path of the clip being recorded, when known before it stops (direct
  /// USB). Lets the controller delete a partial file if the camera is lost.
  String? get activeRecordingPath;

  Future<void> startImageStream(void Function(CameraImage) onFrame);
  Future<void> stopImageStream();

  /// Starts recording. Keeps streaming frames to [onFrame] when given.
  Future<void> startRecording({void Function(CameraImage)? onFrame});

  /// Stops and returns the clip's file path.
  Future<String> stopRecording();

  /// Emits when the camera is lost (unplugged, error, power drop).
  Stream<CameraLost> get lost;

  Future<void> dispose();
}

/// Creates the gateway that opens [choice].
typedef CameraGatewayFactory = CameraGateway Function(CameraChoice choice);
