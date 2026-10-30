import 'body_sides.dart';
import 'capture_step.dart';
import 'support_report.dart';

enum MovementCaptureStatus {
  /// The session reached its end and every recorded step was uploaded.
  /// (Skipped steps have no analysis ID.)
  completed,

  /// The user or operator left before finishing.
  cancelled,

  /// checkSupport() found a blocking issue; the camera was never opened.
  unsupported,
}

class CaptureStepResult {
  const CaptureStepResult({
    required this.step,
    this.analysisId,
    this.skipped = false,
    this.retakes = 0,
    this.sideChoice = SideChoice.both,
  });

  final CaptureStep step;

  /// Server analysis ID, or null if the step was skipped or not finished.
  final String? analysisId;
  final bool skipped;

  /// How many times "Record again" was chosen for this step.
  final int retakes;

  /// Which sides the person chose for a hands or feet step. Always [SideChoice.both]
  /// for other steps.
  final SideChoice sideChoice;

  /// Outcome for one side. A side left out by choice is never "failed".
  SideStatus statusOf(BodySide side) {
    if (skipped) return SideStatus.skipped;
    if (!sideChoice.sides.contains(side)) return SideStatus.notScannedByChoice;
    return analysisId != null ? SideStatus.scanned : SideStatus.failed;
  }
}

class MovementCaptureResult {
  const MovementCaptureResult({
    required this.status,
    required this.support,
    this.steps = const [],
  });

  factory MovementCaptureResult.unsupported(SupportReport support) =>
      MovementCaptureResult(
          status: MovementCaptureStatus.unsupported, support: support);

  factory MovementCaptureResult.cancelled(
    SupportReport support, {
    List<CaptureStepResult> steps = const [],
  }) =>
      MovementCaptureResult(
        status: MovementCaptureStatus.cancelled,
        support: support,
        steps: steps,
      );

  final MovementCaptureStatus status;
  final SupportReport support;
  final List<CaptureStepResult> steps;

  /// First uploaded analysis ID, for hosts that only need one.
  String? get analysisId {
    for (final s in steps) {
      if (s.analysisId != null) return s.analysisId;
    }
    return null;
  }
}
