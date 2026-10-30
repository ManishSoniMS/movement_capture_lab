import 'capture_issue.dart';
import 'hand_topology.dart';

/// One side of the person's body, as the person sees it.
enum BodySide { left, right }

/// Which sides the person chose to scan in a hands or feet step.
enum SideChoice {
  both('both', {BodySide.left, BodySide.right}),
  leftOnly('left', {BodySide.left}),
  rightOnly('right', {BodySide.right});

  const SideChoice(this.wire, this.sides);

  /// Value sent to the backend (`sides` form field).
  final String wire;

  /// The sides that are recorded. Never inferred from which files exist.
  final Set<BodySide> sides;

  /// Missing or unknown values read as [both], so data saved before this
  /// field existed still loads as "both sides captured".
  static SideChoice fromWire(String? value) => SideChoice.values.firstWhere(
        (c) => c.wire == value,
        orElse: () => SideChoice.both,
      );
}

/// What happened to one side in a finished session.
enum SideStatus {
  scanned,

  /// The person chose not to scan this side. Not a failure.
  notScannedByChoice,

  /// The side was meant to be scanned but no upload completed.
  failed,

  /// The whole step was skipped.
  skipped,
}

/// The hand-tracking issue for one frame, or null when the frame is fine.
///
/// MediaPipe labels hands as if the image were mirrored, so the label is
/// converted with [personSide] (which accounts for [framesMirrored]).
CaptureIssue? handSideIssue({
  required SideChoice choice,
  required List<HandSnapshot> hands,
  required bool framesMirrored,
  required bool requireBoth,
}) {
  if (hands.isEmpty) return CaptureIssue.noHands;
  switch (choice) {
    case SideChoice.both:
      return hands.length < 2 && requireBoth ? CaptureIssue.oneHand : null;
    case SideChoice.leftOnly:
      return _sees(hands, 'left', framesMirrored)
          ? null
          : CaptureIssue.showLeftHand;
    case SideChoice.rightOnly:
      return _sees(hands, 'right', framesMirrored)
          ? null
          : CaptureIssue.showRightHand;
  }
}

bool _sees(List<HandSnapshot> hands, String side, bool framesMirrored) =>
    hands.any((h) =>
        personSide(h.handedness, framesMirrored: framesMirrored) == side);
