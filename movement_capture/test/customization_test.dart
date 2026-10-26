import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

void main() {
  const strings = MovementCaptureStrings();
  const icons = MovementCaptureIcons();

  test('every issue has a message and an icon', () {
    for (final issue in CaptureIssue.values) {
      expect(strings.issue(issue), isNotEmpty, reason: '$issue');
      expect(icons.issue(issue), isNotNull, reason: '$issue');
    }
  });

  test('every step has a title, an instruction and an icon', () {
    for (final step in CaptureStep.values) {
      expect(strings.stepTitle(step), isNotEmpty);
      expect(strings.stepInstruction(step), contains('Start'));
      expect(icons.step(step), isNotNull);
    }
  });

  test('step progress counts from 1 and names the step', () {
    expect(strings.stepProgress(1, 4, CaptureStep.face), 'Step 2 of 4 · Face');
  });

  test('saved note names the finished step', () {
    expect(strings.stepSaved(CaptureStep.fullBody), 'Saved: Full body');
  });
}
