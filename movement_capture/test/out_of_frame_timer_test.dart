import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/capture_issue.dart';
import 'package:movement_capture/src/domain/out_of_frame_timer.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  OutOfFrameTimer make() => OutOfFrameTimer(
        grace: const Duration(milliseconds: 400),
        stopAfter: const Duration(seconds: 2),
      );

  test('good frames give nothing', () {
    final t = make();
    expect(t.feed(null, at(0)), isA<OutOfFrameNone>());
    expect(t.feed(null, at(500)), isA<OutOfFrameNone>());
  });

  test('a bad stretch shorter than the grace never starts the warning', () {
    final t = make();
    expect(t.feed(CaptureIssue.noPerson, at(0)), isA<OutOfFrameNone>());
    expect(t.feed(CaptureIssue.noPerson, at(399)), isA<OutOfFrameNone>());
    expect(t.feed(null, at(450)), isA<OutOfFrameNone>());
    // And the bad clock restarted: a new bad frame starts from zero.
    expect(t.feed(CaptureIssue.noPerson, at(500)), isA<OutOfFrameNone>());
    expect(t.feed(CaptureIssue.noPerson, at(850)), isA<OutOfFrameNone>());
  });

  test('warning starts after the grace and counts down', () {
    final t = make();
    t.feed(CaptureIssue.outOfFrame, at(0));
    final w1 = t.feed(CaptureIssue.outOfFrame, at(400));
    expect(w1, isA<OutOfFrameWarning>());
    expect(
        (w1 as OutOfFrameWarning).timeLeft, const Duration(milliseconds: 1600));
    expect(w1.secondsLeft, 2);
    final w2 = t.feed(CaptureIssue.outOfFrame, at(1000)) as OutOfFrameWarning;
    expect(w2.timeLeft, const Duration(milliseconds: 1000));
    expect(w2.secondsLeft, 1);
  });

  test('recovery before the time runs out clears the warning', () {
    final t = make();
    t.feed(CaptureIssue.noPerson, at(0));
    expect(t.feed(CaptureIssue.noPerson, at(1500)), isA<OutOfFrameWarning>());
    expect(t.feed(null, at(1600)), isA<OutOfFrameNone>());
    // A later absence starts a full new period.
    t.feed(CaptureIssue.noPerson, at(2000));
    final w = t.feed(CaptureIssue.noPerson, at(2500)) as OutOfFrameWarning;
    expect(w.timeLeft, const Duration(milliseconds: 1500));
  });

  test('stop fires at stopAfter, with the issue', () {
    final t = make();
    t.feed(CaptureIssue.noFace, at(0));
    expect(t.feed(CaptureIssue.noFace, at(1999)), isA<OutOfFrameWarning>());
    final s = t.feed(CaptureIssue.noFace, at(2000));
    expect(s, isA<OutOfFrameStop>());
    expect((s as OutOfFrameStop).issue, CaptureIssue.noFace);
  });

  test('reset forgets everything', () {
    final t = make();
    t.feed(CaptureIssue.noPerson, at(0));
    t.reset();
    expect(t.feed(CaptureIssue.noPerson, at(2500)), isA<OutOfFrameNone>());
  });
}
