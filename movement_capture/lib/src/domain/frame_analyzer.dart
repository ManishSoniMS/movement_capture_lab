import 'package:camera/camera.dart';

import 'capture_step.dart';
import 'config.dart';
import 'frame_metrics.dart';

/// Yes/no quality gate for one camera frame. Never used for movement analysis.
///
/// Implemented in the data layer (ML Kit); the controller depends only on this
/// interface so tests can substitute a fake.
abstract interface class FrameAnalyzer {
  /// One analyzer per step: each step needs different detectors.
  CaptureStep get step;

  /// Returns null when the frame is skipped (busy or throttled).
  /// Throws [UnsupportedFrameFormat] when the stream format is unusable.
  Future<FrameCheck?> analyze(CameraImage image);

  Future<void> close();
}

/// Creates the analyzer for one step. The controller calls this whenever the
/// step changes.
typedef FrameAnalyzerFactory = FrameAnalyzer Function(
  MovementCaptureConfig config, {
  required CaptureStep step,
  required int Function() rotationDegrees,
  required Duration interval,
});
