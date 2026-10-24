import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/quality_timer.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 10);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('a single bad frame is not confirmed', () {
    final q = QualityTimer(grace: const Duration(milliseconds: 400));
    expect(q.feed(CaptureIssue.outOfFrame, at(0)).confirmedBad, isFalse);
    expect(q.feed(null, at(150)).confirmedBad, isFalse);
  });

  test('failure is confirmed after the grace period', () {
    final q = QualityTimer(grace: const Duration(milliseconds: 400));
    q.feed(CaptureIssue.tooDark, at(0));
    expect(q.feed(CaptureIssue.tooDark, at(399)).confirmedBad, isFalse);
    final r = q.feed(CaptureIssue.tooDark, at(400));
    expect(r.confirmedBad, isTrue);
    expect(r.lastIssue, CaptureIssue.tooDark);
  });

  test('changing issue type does not restart the grace window', () {
    final q = QualityTimer(grace: const Duration(milliseconds: 400));
    q.feed(CaptureIssue.tooDark, at(0));
    final r = q.feed(CaptureIssue.outOfFrame, at(450));
    expect(r.confirmedBad, isTrue);
    expect(r.lastIssue, CaptureIssue.outOfFrame);
  });

  test('good duration accumulates and resets on a bad frame', () {
    final q = QualityTimer(grace: const Duration(milliseconds: 400));
    q.feed(null, at(0));
    expect(q.feed(null, at(1500)).goodFor, const Duration(milliseconds: 1500));
    q.feed(CaptureIssue.noPerson, at(1600));
    expect(q.feed(null, at(1700)).goodFor, Duration.zero);
    expect(q.feed(null, at(2700)).goodFor, const Duration(milliseconds: 1000));
  });

  test('restartGoodWindow requires a fresh window', () {
    final q = QualityTimer(grace: const Duration(milliseconds: 400));
    q.feed(null, at(0));
    q.restartGoodWindow();
    expect(q.feed(null, at(2000)).goodFor, Duration.zero);
    expect(q.feed(null, at(3500)).goodFor, const Duration(milliseconds: 1500));
  });
}
