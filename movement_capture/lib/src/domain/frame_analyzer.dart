import 'package:camera/camera.dart';

import 'frame_metrics.dart';

/// Yes/no quality gate for one camera frame. Never used for movement analysis.
///
/// Implemented in the data layer (ML Kit); the controller depends only on this
/// interface so tests can substitute a fake.
abstract interface class FrameAnalyzer {
  /// Returns null when the frame is skipped (busy or throttled).
  /// Throws [UnsupportedFrameFormat] when the stream format is unusable.
  Future<FrameCheck?> analyze(CameraImage image);

  Future<void> close();
}
