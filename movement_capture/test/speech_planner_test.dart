import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/capture_state.dart';
import 'package:movement_capture/src/presentation/speech_planner.dart';

void main() {
  const strings = MovementCaptureStrings();
  final t0 = DateTime(2026, 1, 1, 10);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  SpeechSnapshot snap(CaptureState s,
          {int index = 0,
          CaptureStep step = CaptureStep.fullBody,
          CaptureStep? saved}) =>
      SpeechSnapshot(state: s, step: step, stepIndex: index, lastSaved: saved);

  Recording rec(int s) => Recording(
      elapsed: Duration(seconds: s), total: const Duration(seconds: 30));

  test('a full step speaks each event once, in order', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    final spoken = <String?>[
      p.next(snap(const Checking()), at(0)),
      p.next(snap(const Checking()), at(100)), // same state: silent
      p.next(snap(const Checking(armed: true)), at(200)),
      p.next(snap(const CountingDown(5)), at(300)),
      p.next(snap(const CountingDown(4)), at(1300)),
      p.next(snap(rec(0)), at(5300)),
      p.next(snap(rec(1)), at(6300)),
    ];
    expect(spoken, [
      strings.selfStepInstructionFullBody,
      null,
      strings.selfHintArmed,
      'Starting in 5',
      '4',
      strings.voiceRecording,
      null,
    ]);
  });

  test('a problem repeats only after the repeat interval', () {
    final p = SpeechPlanner(
        strings: strings,
        mode: CaptureMode.selfGuided,
        issueRepeat: const Duration(seconds: 6));
    const tooDark = Checking(armed: true, issue: CaptureIssue.tooDark);
    expect(p.next(snap(tooDark), at(0)), strings.issueTooDark);
    expect(p.next(snap(tooDark), at(3000)), isNull);
    expect(p.next(snap(tooDark), at(6000)), strings.issueTooDark);
  });

  test('a different problem is spoken at once', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    p.next(
        snap(const Checking(armed: true, issue: CaptureIssue.tooDark)), at(0));
    expect(
        p.next(snap(const Checking(armed: true, issue: CaptureIssue.noPerson)),
            at(500)),
        strings.issueNoPerson);
  });

  test('clearing a problem while waiting says "good"', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    p.next(snap(const Checking(armed: true, issue: CaptureIssue.outOfFrame)),
        at(0));
    expect(
        p.next(snap(const Checking(armed: true)), at(800)), strings.voiceGood);
  });

  test('next step is introduced with "Done." and the self-guided text', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    p.next(snap(const Checking()), at(0));
    expect(
      p.next(
          snap(const Checking(),
              index: 1, step: CaptureStep.face, saved: CaptureStep.fullBody),
          at(100)),
      '${strings.voiceStepDone} ${strings.selfStepInstructionFace}',
    );
  });

  test('assisted mode uses the helper wording', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.assisted);
    expect(
        p.next(snap(const Checking()), at(0)), strings.stepInstructionFullBody);
  });

  test('self-guided backlit wording addresses the user', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    expect(p.next(snap(const Checking(issue: CaptureIssue.backlit)), at(0)),
        strings.selfIssueBacklit);
  });

  test('end of session is announced once', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    expect(p.next(snap(const Finishing(0.2)), at(0)), strings.voiceFinishing);
    expect(p.next(snap(const Finishing(0.6)), at(500)), isNull);
    expect(p.next(snap(const SessionComplete()), at(900)), strings.completed);
  });

  test('recording without live checks speaks the notice', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    expect(
        p.next(
            snap(const Recording(
                elapsed: Duration.zero,
                total: Duration(seconds: 30),
                liveChecks: false)),
            at(0)),
        strings.noLiveChecksNotice);
  });

  test('needs-help and camera problems are spoken once', () {
    final p = SpeechPlanner(strings: strings, mode: CaptureMode.selfGuided);
    final help = snap(const NeedsOperator(CaptureIssue.tooDark));
    expect(p.next(help, at(0)), strings.selfNeedsOperator);
    expect(p.next(help, at(100)), isNull);
    final cam = snap(const CameraUnavailable(CameraFailure.noCamera));
    expect(p.next(cam, at(200)), strings.cameraNone);
    expect(p.next(cam, at(300)), isNull);
  });
}
