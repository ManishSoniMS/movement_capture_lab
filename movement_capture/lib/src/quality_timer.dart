import 'capture_issue.dart';

class QualityReading {
  const QualityReading({
    required this.confirmedBad,
    required this.goodFor,
    required this.lastIssue,
  });

  /// Failures have continued for at least the grace period.
  final bool confirmedBad;

  /// How long frames have been continuously good (zero while failing).
  final Duration goodFor;

  /// Most recent failing issue, if any.
  final CaptureIssue? lastIssue;
}

/// Turns a stream of per-frame results into debounced decisions.
/// One bad frame never confirms a failure.
class QualityTimer {
  QualityTimer({required this.grace});

  final Duration grace;
  DateTime? _goodSince;
  DateTime? _badSince;
  CaptureIssue? _lastIssue;

  void reset() {
    _goodSince = null;
    _badSince = null;
    _lastIssue = null;
  }

  /// Requires a fresh good window from the next good frame.
  void restartGoodWindow() => _goodSince = null;

  QualityReading feed(CaptureIssue? issue, DateTime at) {
    if (issue == null) {
      _badSince = null;
      _goodSince ??= at;
    } else {
      _goodSince = null;
      _badSince ??= at;
      _lastIssue = issue;
    }
    return QualityReading(
      confirmedBad: _badSince != null && at.difference(_badSince!) >= grace,
      goodFor: _goodSince == null ? Duration.zero : at.difference(_goodSince!),
      lastIssue: _lastIssue,
    );
  }
}
