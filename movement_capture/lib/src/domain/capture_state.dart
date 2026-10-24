import 'capture_issue.dart';

sealed class CaptureState {
  const CaptureState();
}

final class Initializing extends CaptureState {
  const Initializing();
}

enum CameraFailure { notConnected, permissionDenied, streamUnsupported, other }

final class CameraUnavailable extends CaptureState {
  const CameraUnavailable(this.reason);
  final CameraFailure reason;
}

final class Checking extends CaptureState {
  const Checking({this.issue, this.armed = false, this.interrupted = false});

  /// Confirmed issue currently shown, or null when conditions are good.
  final CaptureIssue? issue;

  /// True after the operator tapped Start.
  final bool armed;

  /// True when a recording was just stopped by [issue].
  final bool interrupted;
}

final class CountingDown extends CaptureState {
  const CountingDown(this.secondsLeft);
  final int secondsLeft;
}

final class Recording extends CaptureState {
  const Recording({required this.elapsed, required this.total});
  final Duration elapsed;
  final Duration total;

  double get progress {
    if (total.inMilliseconds == 0) return 0;
    final p = elapsed.inMilliseconds / total.inMilliseconds;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }
}

final class NeedsOperator extends CaptureState {
  const NeedsOperator(this.lastIssue);
  final CaptureIssue lastIssue;
}

final class Uploading extends CaptureState {
  const Uploading(this.progress);
  final double progress;
}

final class UploadFailed extends CaptureState {
  const UploadFailed();
}

final class Completed extends CaptureState {
  const Completed(this.analysisId);
  final String analysisId;
}
