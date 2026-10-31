import 'config.dart';

/// Whether the active camera's video meets the minimum for analysis.
/// [width] and [height] may come in either orientation; the short side is
/// compared. [fps] is the measured frame rate of the image stream.
bool cameraIsGoodEnough({
  required MovementCaptureConfig config,
  required int width,
  required int height,
  required double fps,
}) {
  final shortSide = width < height ? width : height;
  return shortSide >= config.minCameraShortSide && fps >= config.minCameraFps;
}

/// Measures the stream frame rate once. Feed it one timestamp per frame; it
/// returns the rate when [window] has passed since the first frame, and null
/// before that and after it has reported.
class FrameRateMeter {
  FrameRateMeter(this.window);

  final Duration window;
  DateTime? _first;
  int _count = 0;
  bool _done = false;

  double? add(DateTime at) {
    if (_done) return null;
    _first ??= at;
    _count++;
    final elapsed = at.difference(_first!);
    if (elapsed < window) return null;
    _done = true;
    return _count / (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
  }
}
