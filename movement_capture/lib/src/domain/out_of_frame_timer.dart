import 'capture_issue.dart';

/// Result of feeding one frame to [OutOfFrameTimer].
sealed class OutOfFrameSignal {
  const OutOfFrameSignal();
}

/// Nothing to show: in frame, or out for less than the grace.
final class OutOfFrameNone extends OutOfFrameSignal {
  const OutOfFrameNone();
}

/// Out of frame: tell the person, with the time left before the stop.
final class OutOfFrameWarning extends OutOfFrameSignal {
  const OutOfFrameWarning(this.timeLeft);
  final Duration timeLeft;

  /// Whole seconds for the on-screen countdown (rounded up, so the last
  /// second still reads 1).
  int get secondsLeft => (timeLeft.inMilliseconds / 1000).ceil();
}

/// The time ran out: stop now.
final class OutOfFrameStop extends OutOfFrameSignal {
  const OutOfFrameStop(this.issue);
  final CaptureIssue issue;
}

/// Counts how long the subject has been out of frame during recording.
///
/// Feed it the out-of-frame issue (or null when in frame) of every analysed
/// frame. A bad stretch shorter than [grace] is ignored, like [QualityTimer].
/// After that a warning with the time left is returned; at [stopAfter] (counted
/// from the first bad frame) it returns [OutOfFrameStop]. Coming back in time
/// clears everything.
class OutOfFrameTimer {
  OutOfFrameTimer({required this.grace, required this.stopAfter});

  final Duration grace;
  final Duration stopAfter;

  DateTime? _badSince;

  void reset() => _badSince = null;

  OutOfFrameSignal feed(CaptureIssue? issue, DateTime at) {
    if (issue == null) {
      _badSince = null;
      return const OutOfFrameNone();
    }
    final since = _badSince ??= at;
    final elapsed = at.difference(since);
    if (elapsed >= stopAfter) return OutOfFrameStop(issue);
    if (elapsed >= grace) return OutOfFrameWarning(stopAfter - elapsed);
    return const OutOfFrameNone();
  }
}
