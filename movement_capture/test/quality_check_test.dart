import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/luma_stats.dart';
import 'package:movement_capture/src/domain/luma_thumb.dart';
import 'package:movement_capture/src/domain/quality_status.dart';
import 'package:movement_capture/src/domain/quality_summary.dart';

/// Synthetic Y plane, one byte per pixel, `bytesPerRow == width`.
LumaThumb _thumb(int w, int h, int Function(int x, int y) at) {
  final bytes = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bytes[y * w + x] = at(x, y);
    }
  }
  return LumaThumb.fromLumaPlane(bytes, width: w, height: h, bytesPerRow: w);
}

LumaStats _luma(double mean) =>
    LumaStats(mean: mean, clippedFraction: 0, centerToBorder: 1); // evenly lit

void main() {
  final config = MovementCaptureConfig();

  group('LumaThumb', () {
    test('is downscaled so the longest side is at most the limit', () {
      final t = _thumb(640, 480, (x, y) => 100);
      expect(t.width, 160);
      expect(t.height, 120);
    });

    test('a small frame is not upscaled', () {
      final t = _thumb(80, 60, (x, y) => 100);
      expect((t.width, t.height), (80, 60));
    });

    test('a blurred frame is less sharp than a crisp one', () {
      final crisp = _thumb(160, 120, (x, y) => (x ~/ 4).isEven ? 40 : 220);
      final blurred = _thumb(160, 120, (x, y) => 130 + ((x % 8) - 4) * 4);
      final flat = _thumb(160, 120, (x, y) => 128);
      expect(crisp.sharpness, greaterThan(blurred.sharpness));
      expect(blurred.sharpness, greaterThan(flat.sharpness));
      expect(flat.sharpness, 0);
    });

    test('identical frames show no motion; a shifted frame does', () {
      int stripes(int x, int y) => (x ~/ 8).isEven ? 40 : 220;
      final a = _thumb(160, 120, stripes);
      final same = _thumb(160, 120, stripes);
      final shifted = _thumb(160, 120, (x, y) => stripes(x + 8, y));
      expect(same.motionFrom(a), 0);
      expect(shifted.motionFrom(a), greaterThan(config.maxMotion));
    });

    test('motion against no previous frame, or a different size, is zero', () {
      final a = _thumb(160, 120, (x, y) => 100);
      expect(a.motionFrom(null), 0);
      expect(a.motionFrom(_thumb(80, 60, (x, y) => 200)), 0);
    });
  });

  group('assessQuality', () {
    QualityReading assess({
      Set<CaptureIssue> issues = const {},
      LumaStats? luma,
      double sharpness = 500,
      double motion = 0,
      double? subjectFraction,
      CaptureStep step = CaptureStep.fullBody,
    }) =>
        assessQuality(
          config: config,
          step: step,
          issues: issues,
          luma: luma ?? _luma(120),
          sharpness: sharpness,
          motion: motion,
          subjectFraction: subjectFraction,
        );

    test('everything fine: in frame and no problem', () {
      final r = assess();
      expect(r.inFrame, isTrue);
      expect(r.problems, isEmpty);
      expect(r.problem, isNull);
    });

    test('detector issues that mean "not in frame"', () {
      for (final i in [
        CaptureIssue.noPerson,
        CaptureIssue.noFace,
        CaptureIssue.noHands,
        CaptureIssue.outOfFrame,
      ]) {
        expect(assess(issues: {i}).inFrame, isFalse, reason: '$i');
      }
    });

    test('dark and bright frames', () {
      expect(assess(luma: _luma(config.minMeanLuma - 1.0)).problem,
          QualityProblem.tooDark);
      expect(assess(luma: _luma(config.maxMeanLuma + 1.0)).problem,
          QualityProblem.tooBright);
    });

    test('blur and movement use the thresholds from config', () {
      expect(assess(sharpness: config.minSharpness - 1).problems,
          {QualityProblem.blurry});
      expect(assess(motion: config.maxMotion + 1).problems,
          {QualityProblem.moving});
      final strict = MovementCaptureConfig(minSharpness: 900, maxMotion: 1);
      final r = assessQuality(
        config: strict,
        step: CaptureStep.fullBody,
        issues: const {},
        luma: _luma(120),
        sharpness: 500,
        motion: 2,
        subjectFraction: null,
      );
      expect(r.problems, {QualityProblem.blurry, QualityProblem.moving});
    });

    test('distance: face width and body height each have a range', () {
      expect(assess(step: CaptureStep.face, subjectFraction: 0.1).problem,
          QualityProblem.tooFar);
      expect(assess(step: CaptureStep.face, subjectFraction: 0.95).problem,
          QualityProblem.tooClose);
      expect(assess(step: CaptureStep.face, subjectFraction: 0.4).problems,
          isEmpty);
      expect(assess(subjectFraction: 0.2).problem, QualityProblem.tooFar);
      expect(assess(subjectFraction: 0.99).problem, QualityProblem.tooClose);
    });

    test('hands and feet have no distance check', () {
      for (final s in [CaptureStep.hands, CaptureStep.feet]) {
        expect(assess(step: s, subjectFraction: 0.01).problems, isEmpty);
      }
    });

    test('with several problems the highest priority wins', () {
      final r = assess(
          luma: _luma(10), sharpness: 0, motion: 100); // dark, blurry, moving
      expect(r.problems.length, 3);
      expect(r.problem, QualityProblem.tooDark);
    });
  });

  group('VerdictHold (no flicker)', () {
    final t0 = DateTime(2026, 1, 1);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('the first value is shown straight away', () {
      final h = VerdictHold<bool>(const Duration(milliseconds: 500));
      expect(h.feed(true, at(0)), isTrue);
    });

    test('one bad sample does not change what is shown', () {
      final h = VerdictHold<bool>(const Duration(milliseconds: 500));
      h.feed(true, at(0));
      expect(h.feed(false, at(100)), isTrue);
      expect(h.feed(true, at(200)), isTrue);
      expect(h.feed(false, at(300)), isTrue); // the clock restarted
      expect(h.feed(false, at(700)), isTrue); // only 400 ms
    });

    test('a sustained change shows after the hold time', () {
      final h = VerdictHold<bool>(const Duration(milliseconds: 500));
      h.feed(true, at(0));
      h.feed(false, at(100));
      expect(h.feed(false, at(599)), isTrue);
      expect(h.feed(false, at(600)), isFalse);
    });

    test('the hold time comes from config', () {
      expect(config.qualityHold, const Duration(milliseconds: 500));
      expect(
          MovementCaptureConfig(qualityHold: const Duration(seconds: 1))
              .qualityHold,
          const Duration(seconds: 1));
    });
  });

  group('QualitySummary', () {
    QualitySample s(int ms, {bool inFrame = true, Set<QualityProblem>? p}) =>
        QualitySample(tMs: ms, inFrame: inFrame, problems: p ?? const {});

    test('shares are weighted by time between samples', () {
      // 0–1000 in frame, 1000–4000 out of frame, 4000–5000 in frame.
      final summary = QualitySummary.from(
        [s(0), s(1000, inFrame: false), s(4000)],
        durationMs: 5000,
        config: config,
      );
      expect(summary.inFrameShare, closeTo(0.4, 1e-9));
      expect(summary.passShare[QualityProblem.blurry], 1.0);
    });

    test('good recording passes', () {
      final summary = QualitySummary.from(
        [for (var t = 0; t < 10000; t += 300) s(t)],
        durationMs: 10000,
        config: config,
      );
      expect(summary.passes, isTrue);
      expect(summary.failure, isNull);
    });

    test('out of frame too long fails with that as the reason', () {
      final summary = QualitySummary.from(
        [for (var t = 0; t < 10000; t += 300) s(t, inFrame: t < 6000)],
        durationMs: 10000,
        config: config,
      );
      expect(summary.passes, isFalse);
      expect(summary.failure, SummaryFailure.outOfFrame);
    });

    test('a quality check that fails too often fails the recording', () {
      final summary = QualitySummary.from(
        [
          for (var t = 0; t < 10000; t += 300)
            s(t, p: t < 5000 ? {QualityProblem.tooDark} : const {})
        ],
        durationMs: 10000,
        config: config,
      );
      expect(summary.passes, isFalse);
      expect(summary.failure, SummaryFailure.problem);
      expect(summary.worstProblem, QualityProblem.tooDark);
    });

    test('pass rules come from config', () {
      final lenient = MovementCaptureConfig(minInFrameShare: 0.3);
      final samples = [
        for (var t = 0; t < 10000; t += 300) s(t, inFrame: t < 6000)
      ];
      expect(
          QualitySummary.from(samples, durationMs: 10000, config: lenient)
              .passes,
          isTrue);
    });

    test('too short a recording fails', () {
      final summary = QualitySummary.from(
        [s(0), s(300)],
        durationMs: config.minRecordedDuration.inMilliseconds - 1,
        config: config,
      );
      expect(summary.failure, SummaryFailure.tooShort);
    });

    test('no samples (checks were off) does not claim a pass or a failure', () {
      final summary =
          QualitySummary.from(const [], durationMs: 10000, config: config);
      expect(summary.measured, isFalse);
      expect(summary.passes, isTrue);
    });

    test('toJson carries the numbers for the backend/ML team', () {
      final summary = QualitySummary.from(
        [s(0), s(1000, inFrame: false)],
        durationMs: 2000,
        config: config,
      );
      final j = summary.toJson();
      expect(j['inFrameShare'], closeTo(0.5, 1e-9));
      expect(j['durationMs'], 2000);
      expect(j['passes'], isFalse);
      expect((j['passShare'] as Map).keys, contains('tooDark'));
    });
  });

  test('blocking on poor quality is off by default', () {
    expect(config.blockOnPoorQuality, isFalse);
    expect(config.allowUseAnyway, isTrue);
  });
}
