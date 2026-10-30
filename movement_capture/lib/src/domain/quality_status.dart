import 'capture_issue.dart';
import 'capture_step.dart';
import 'config.dart';
import 'luma_stats.dart';

/// Why a video would not be good enough for analysis. Declared in display
/// priority order: when several apply, the first one is shown.
enum QualityProblem { tooDark, tooBright, tooFar, tooClose, blurry, moving }

/// Detector issues that mean the subject is not (fully) in the frame.
const Set<CaptureIssue> _notInFrame = {
  CaptureIssue.noPerson,
  CaptureIssue.noFace,
  CaptureIssue.noHands,
  CaptureIssue.oneHand,
  CaptureIssue.showLeftHand,
  CaptureIssue.showRightHand,
  CaptureIssue.outOfFrame,
};

/// What one analysed frame says about the video: is the subject in frame, and
/// which quality checks failed.
class QualityReading {
  const QualityReading({required this.inFrame, required this.problems});

  final bool inFrame;
  final Set<QualityProblem> problems;

  QualityProblem? get problem {
    for (final p in QualityProblem.values) {
      if (problems.contains(p)) return p;
    }
    return null;
  }
}

/// Pure verdict for one frame. [subjectFraction] is the face width (face
/// step) or the body height (full-body step) as a share of the frame; null
/// when the step has no detector for it, which skips the distance check.
QualityReading assessQuality({
  required MovementCaptureConfig config,
  required CaptureStep step,
  required Set<CaptureIssue> issues,
  required LumaStats luma,
  required double sharpness,
  required double motion,
  required double? subjectFraction,
}) {
  final problems = <QualityProblem>{};
  switch (luma.issueFor(config)) {
    case CaptureIssue.tooDark || CaptureIssue.backlit:
      problems.add(QualityProblem.tooDark);
    case CaptureIssue.tooBright:
      problems.add(QualityProblem.tooBright);
    default:
      break;
  }
  if (subjectFraction != null) {
    final (min, max) = switch (step) {
      CaptureStep.face => (
          config.faceMinWidthFraction,
          config.faceMaxWidthFraction
        ),
      CaptureStep.fullBody => (
          config.bodyMinHeightFraction,
          config.bodyMaxHeightFraction
        ),
      _ => (0.0, double.infinity),
    };
    if (subjectFraction < min) problems.add(QualityProblem.tooFar);
    if (subjectFraction > max) problems.add(QualityProblem.tooClose);
  }
  if (sharpness < config.minSharpness) problems.add(QualityProblem.blurry);
  if (motion > config.maxMotion) problems.add(QualityProblem.moving);
  return QualityReading(
    inFrame: !issues.any(_notInFrame.contains),
    problems: problems,
  );
}

/// Shows a value only after it has held for [hold]. One odd sample never
/// changes what is shown, so the status does not blink.
class VerdictHold<T> {
  VerdictHold(this.hold);

  final Duration hold;
  T? _shown;
  bool _hasShown = false;
  T? _candidate;
  DateTime? _candidateSince;

  T feed(T value, DateTime at) {
    if (!_hasShown) {
      _hasShown = true;
      return _shown = value;
    }
    if (value == _shown) {
      _candidateSince = null;
      return _shown as T;
    }
    if (_candidateSince == null || value != _candidate) {
      _candidate = value;
      _candidateSince = at;
    }
    if (at.difference(_candidateSince!) >= hold) {
      _shown = value;
      _candidateSince = null;
    }
    return _shown as T;
  }

  void reset() {
    _hasShown = false;
    _shown = null;
    _candidate = null;
    _candidateSince = null;
  }
}

/// What the patient sees: debounced in-frame flag and top problem.
class QualityStatus {
  const QualityStatus({required this.inFrame, required this.problem});

  final bool inFrame;
  final QualityProblem? problem;

  bool get good => inFrame && problem == null;

  @override
  bool operator ==(Object other) =>
      other is QualityStatus &&
      other.inFrame == inFrame &&
      other.problem == problem;

  @override
  int get hashCode => Object.hash(inFrame, problem);
}

/// Turns raw per-frame readings into a steady [QualityStatus].
class QualityStatusTracker {
  QualityStatusTracker(Duration hold)
      : _inFrame = VerdictHold(hold),
        _problem = VerdictHold(hold);

  final VerdictHold<bool> _inFrame;
  final VerdictHold<QualityProblem?> _problem;

  QualityStatus feed(QualityReading r, DateTime at) => QualityStatus(
        inFrame: _inFrame.feed(r.inFrame, at),
        problem: _problem.feed(r.problem, at),
      );

  void reset() {
    _inFrame.reset();
    _problem.reset();
  }
}
