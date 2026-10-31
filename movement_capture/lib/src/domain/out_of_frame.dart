import 'body_sides.dart';
import 'capture_issue.dart';
import 'capture_step.dart';

/// True when [issue] means the subject is not (fully) in the picture for
/// [step]. These are the only issues "Stop recording if out of frame" reacts
/// to. Everything else (several people, wrong hand, distance, lighting,
/// sharpness, movement) stays under `blockOnPoorQuality` only.
///
/// | Step      | Out of frame                                              |
/// |-----------|-----------------------------------------------------------|
/// | Full body | `noPerson`, `outOfFrame`                                  |
/// | Face      | `noFace`                                                  |
/// | Hands     | `noHands`; `oneHand` only if both hands are required      |
/// | Feet      | none: nothing tracks feet                                 |
bool countsAsOutOfFrame(
  CaptureIssue issue, {
  required CaptureStep step,
  required SideChoice sideChoice,
  required bool requireBothHands,
}) =>
    switch (step) {
      CaptureStep.fullBody =>
        issue == CaptureIssue.noPerson || issue == CaptureIssue.outOfFrame,
      CaptureStep.face => issue == CaptureIssue.noFace,
      CaptureStep.hands => issue == CaptureIssue.noHands ||
          (issue == CaptureIssue.oneHand &&
              requireBothHands &&
              sideChoice == SideChoice.both),
      CaptureStep.feet => false,
    };

/// The highest-priority out-of-frame issue among [issues], or null. Looks at
/// the whole set, because `topIssue` can be a higher-priority issue (several
/// people) that hides an out-of-frame one.
CaptureIssue? outOfFrameIssue(
  Set<CaptureIssue> issues, {
  required CaptureStep step,
  required SideChoice sideChoice,
  required bool requireBothHands,
}) {
  for (final issue in CaptureIssue.values) {
    if (issues.contains(issue) &&
        countsAsOutOfFrame(issue,
            step: step,
            sideChoice: sideChoice,
            requireBothHands: requireBothHands)) {
      return issue;
    }
  }
  return null;
}

/// False for steps where the switch cannot work (feet: nothing tracks them).
bool stepSupportsOutOfFrameStop(CaptureStep step) => step != CaptureStep.feet;

/// What may cancel a countdown or abort a recording.
enum StopRule {
  /// Any confirmed issue, after `violationGrace` (`blockOnPoorQuality`).
  anyIssue,

  /// Only out-of-frame issues, after `outOfFrameStopAfter`.
  outOfFrameOnly,

  /// Nothing stops; the review result reports the time out of frame.
  none,
}

StopRule stopRuleFor({
  required bool blockOnPoorQuality,
  required bool stopWhenOutOfFrame,
}) {
  if (blockOnPoorQuality) return StopRule.anyIssue;
  return stopWhenOutOfFrame ? StopRule.outOfFrameOnly : StopRule.none;
}
