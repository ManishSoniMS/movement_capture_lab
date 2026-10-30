import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/body_sides.dart';
import 'package:movement_capture/src/domain/hand_topology.dart';

HandSnapshot _hand(String handedness) => HandSnapshot(
      handedness: handedness,
      score: 0.9,
      points: List.filled(handPointNames.length, const Offset(0.5, 0.5)),
      depth: List.filled(handPointNames.length, 0),
    );

void main() {
  group('SideChoice wire format', () {
    test('left-only, right-only and both round-trip', () {
      for (final c in SideChoice.values) {
        expect(SideChoice.fromWire(c.wire), c);
      }
    });

    test('a result without the field (old data) loads as both sides', () {
      expect(SideChoice.fromWire(null), SideChoice.both);
      expect(SideChoice.fromWire('something-new'), SideChoice.both);
    });

    test('sides listed explicitly per choice', () {
      expect(SideChoice.both.sides, {BodySide.left, BodySide.right});
      expect(SideChoice.leftOnly.sides, {BodySide.left});
      expect(SideChoice.rightOnly.sides, {BodySide.right});
    });
  });

  group('CaptureStepResult.statusOf', () {
    test('user choice stays different from a failed scan', () {
      const chosen = CaptureStepResult(
          step: CaptureStep.hands,
          analysisId: 'a1',
          sideChoice: SideChoice.leftOnly);
      expect(chosen.statusOf(BodySide.left), SideStatus.scanned);
      expect(chosen.statusOf(BodySide.right), SideStatus.notScannedByChoice);

      const failed = CaptureStepResult(
          step: CaptureStep.hands, sideChoice: SideChoice.leftOnly);
      expect(failed.statusOf(BodySide.left), SideStatus.failed);
      expect(failed.statusOf(BodySide.right), SideStatus.notScannedByChoice);
    });

    test('both sides scanned; a skipped step is not a choice', () {
      const both = CaptureStepResult(step: CaptureStep.feet, analysisId: 'a');
      expect(both.statusOf(BodySide.left), SideStatus.scanned);
      expect(both.statusOf(BodySide.right), SideStatus.scanned);

      const skipped = CaptureStepResult(step: CaptureStep.feet, skipped: true);
      expect(skipped.statusOf(BodySide.left), SideStatus.skipped);
    });
  });

  group('handSideIssue', () {
    CaptureIssue? issue(SideChoice c, List<String> labels,
            {bool mirrored = false, bool requireBoth = true}) =>
        handSideIssue(
          choice: c,
          hands: [for (final l in labels) _hand(l)],
          framesMirrored: mirrored,
          requireBoth: requireBoth,
        );

    test('no hands is always noHands', () {
      for (final c in SideChoice.values) {
        expect(issue(c, []), CaptureIssue.noHands);
      }
    });

    test('both: one hand is oneHand only when both are required', () {
      expect(issue(SideChoice.both, ['Left']), CaptureIssue.oneHand);
      expect(issue(SideChoice.both, ['Left'], requireBoth: false), isNull);
      expect(issue(SideChoice.both, ['Left', 'Right']), isNull);
    });

    // MediaPipe labels as if mirrored. Unmirrored frames: label "Right" is
    // the person's left hand (see personSide).
    test('left only, unmirrored camera: label Right is the left hand', () {
      expect(issue(SideChoice.leftOnly, ['Right']), isNull);
      expect(issue(SideChoice.leftOnly, ['Left']), CaptureIssue.showLeftHand);
    });

    test('left only, mirrored frames: label Left is the left hand', () {
      expect(issue(SideChoice.leftOnly, ['Left'], mirrored: true), isNull);
      expect(issue(SideChoice.leftOnly, ['Right'], mirrored: true),
          CaptureIssue.showLeftHand);
    });

    test('right only asks for the right hand in both camera modes', () {
      expect(
          issue(SideChoice.rightOnly, ['Right']), CaptureIssue.showRightHand);
      expect(issue(SideChoice.rightOnly, ['Left']), isNull);
      expect(issue(SideChoice.rightOnly, ['Left'], mirrored: true),
          CaptureIssue.showRightHand);
      expect(issue(SideChoice.rightOnly, ['Right'], mirrored: true), isNull);
    });
  });
}
