import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/body_sides.dart';
import 'package:movement_capture/src/domain/capture_issue.dart';
import 'package:movement_capture/src/domain/capture_step.dart';
import 'package:movement_capture/src/domain/out_of_frame.dart';

bool _oof(
  CaptureIssue i,
  CaptureStep step, {
  SideChoice choice = SideChoice.both,
  bool both = true,
}) =>
    countsAsOutOfFrame(i,
        step: step, sideChoice: choice, requireBothHands: both);

void main() {
  group('what counts as out of frame', () {
    test('full body: noPerson and outOfFrame only', () {
      for (final i in CaptureIssue.values) {
        expect(_oof(i, CaptureStep.fullBody),
            i == CaptureIssue.noPerson || i == CaptureIssue.outOfFrame,
            reason: '$i');
      }
    });

    test('face: noFace only', () {
      for (final i in CaptureIssue.values) {
        expect(_oof(i, CaptureStep.face), i == CaptureIssue.noFace,
            reason: '$i');
      }
    });

    test('hands: noHands always', () {
      expect(_oof(CaptureIssue.noHands, CaptureStep.hands), isTrue);
      expect(
          _oof(CaptureIssue.noHands, CaptureStep.hands,
              choice: SideChoice.leftOnly),
          isTrue);
    });

    test('hands: oneHand only when both hands are required (Both + flag)', () {
      expect(_oof(CaptureIssue.oneHand, CaptureStep.hands), isTrue);
      expect(
          _oof(CaptureIssue.oneHand, CaptureStep.hands, both: false), isFalse);
      expect(
          _oof(CaptureIssue.oneHand, CaptureStep.hands,
              choice: SideChoice.rightOnly),
          isFalse);
      expect(
          _oof(CaptureIssue.oneHand, CaptureStep.hands,
              choice: SideChoice.leftOnly),
          isFalse);
    });

    test('hands: wrong hand, multiple people, distance, light are not', () {
      for (final i in [
        CaptureIssue.showLeftHand,
        CaptureIssue.showRightHand,
        CaptureIssue.multiplePeople,
        CaptureIssue.faceTooFar,
        CaptureIssue.tooDark,
        CaptureIssue.tooBright,
        CaptureIssue.backlit,
      ]) {
        expect(_oof(i, CaptureStep.hands), isFalse, reason: '$i');
      }
    });

    test('feet: nothing', () {
      for (final i in CaptureIssue.values) {
        expect(_oof(i, CaptureStep.feet), isFalse, reason: '$i');
      }
      expect(stepSupportsOutOfFrameStop(CaptureStep.feet), isFalse);
      expect(stepSupportsOutOfFrameStop(CaptureStep.fullBody), isTrue);
      expect(stepSupportsOutOfFrameStop(CaptureStep.face), isTrue);
      expect(stepSupportsOutOfFrameStop(CaptureStep.hands), isTrue);
    });

    test('picks the out-of-frame issue from the whole set, not the top one',
        () {
      // multiplePeople outranks noPerson in display priority; it must not
      // hide the out-of-frame issue.
      final found = outOfFrameIssue(
        {CaptureIssue.multiplePeople, CaptureIssue.noPerson},
        step: CaptureStep.fullBody,
        sideChoice: SideChoice.both,
        requireBothHands: true,
      );
      expect(found, CaptureIssue.noPerson);
      expect(
          outOfFrameIssue({CaptureIssue.tooDark},
              step: CaptureStep.fullBody,
              sideChoice: SideChoice.both,
              requireBothHands: true),
          isNull);
    });
  });

  group('how the two switches combine', () {
    test('block on: any issue stops, whatever the other switch says', () {
      expect(stopRuleFor(blockOnPoorQuality: true, stopWhenOutOfFrame: false),
          StopRule.anyIssue);
      expect(stopRuleFor(blockOnPoorQuality: true, stopWhenOutOfFrame: true),
          StopRule.anyIssue);
    });
    test('block off, out-of-frame on: only out of frame', () {
      expect(stopRuleFor(blockOnPoorQuality: false, stopWhenOutOfFrame: true),
          StopRule.outOfFrameOnly);
    });
    test('both off: nothing stops', () {
      expect(stopRuleFor(blockOnPoorQuality: false, stopWhenOutOfFrame: false),
          StopRule.none);
    });
  });
}
