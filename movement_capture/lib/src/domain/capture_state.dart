import 'capture_issue.dart';

sealed class CaptureState {
  const CaptureState();
}

final class Initializing extends CaptureState {
  const Initializing();
}

enum CameraFailure { noCamera, permissionDenied, streamUnsupported, other }

final class CameraUnavailable extends CaptureState {
  const CameraUnavailable(this.reason);
  final CameraFailure reason;
}

/// Preview running, checks running. Not armed = waiting for Start (the
/// step's instruction is shown). Armed = waiting for good conditions.
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
  const Recording({
    required this.elapsed,
    required this.total,
    this.liveChecks = true,
  });
  final Duration elapsed;
  final Duration total;

  /// False when this device cannot send frames while recording, so the
  /// recording runs without quality checks.
  final bool liveChecks;

  double get progress {
    if (total.inMilliseconds == 0) return 0;
    final p = elapsed.inMilliseconds / total.inMilliseconds;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }
}

/// Too many automatic restarts in the current step.
final class NeedsOperator extends CaptureState {
  const NeedsOperator(this.lastIssue);
  final CaptureIssue lastIssue;
}

/// All steps recorded or skipped; uploads still running.
final class Finishing extends CaptureState {
  const Finishing(this.progress);
  final double progress;
}

/// All steps recorded or skipped; some uploads failed.
final class FinishFailed extends CaptureState {
  const FinishFailed(this.failedCount);
  final int failedCount;
}

/// Every recorded step uploaded.
final class SessionComplete extends CaptureState {
  const SessionComplete();
}
