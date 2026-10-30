import 'config.dart';
import 'quality_status.dart';

/// One quality sample taken while recording; [tMs] = ms since recording start.
class QualitySample {
  const QualitySample({
    required this.tMs,
    required this.inFrame,
    required this.problems,
  });

  final int tMs;
  final bool inFrame;
  final Set<QualityProblem> problems;
}

/// Why a recording did not pass. In priority order.
enum SummaryFailure { tooShort, outOfFrame, problem }

/// Overall result of one recording, from the samples taken during it.
/// Contains numbers only: no frames, no landmarks.
class QualitySummary {
  const QualitySummary._({
    required this.measured,
    required this.durationMs,
    required this.inFrameShare,
    required this.passShare,
    required this.failure,
    required this.worstProblem,
  });

  /// False when no samples were taken (live checks were off): nothing was
  /// measured, so nothing is claimed.
  final bool measured;
  final int durationMs;

  /// Share of the recording time the subject was in frame (0–1).
  final double inFrameShare;

  /// Per quality check: share of the recording time it passed (0–1).
  final Map<QualityProblem, double> passShare;

  final SummaryFailure? failure;

  /// The check that passed least often, when [failure] is
  /// [SummaryFailure.problem].
  final QualityProblem? worstProblem;

  bool get passes => failure == null;

  /// Each sample counts for the time until the next one; the last one until
  /// the end of the recording.
  factory QualitySummary.from(
    List<QualitySample> samples, {
    required int durationMs,
    required MovementCaptureConfig config,
  }) {
    final tooShort = durationMs < config.minRecordedDuration.inMilliseconds;
    if (samples.isEmpty) {
      return QualitySummary._(
        measured: false,
        durationMs: durationMs,
        inFrameShare: 1,
        passShare: {for (final p in QualityProblem.values) p: 1},
        failure: tooShort ? SummaryFailure.tooShort : null,
        worstProblem: null,
      );
    }
    var total = 0, inFrame = 0;
    final failed = {for (final p in QualityProblem.values) p: 0};
    for (var i = 0; i < samples.length; i++) {
      final end = i + 1 < samples.length ? samples[i + 1].tMs : durationMs;
      final weight = (end - samples[i].tMs).clamp(0, durationMs);
      total += weight;
      if (samples[i].inFrame) inFrame += weight;
      for (final p in samples[i].problems) {
        failed[p] = failed[p]! + weight;
      }
    }
    double share(int part) => total == 0 ? 1 : part / total;
    final pass = {
      for (final p in QualityProblem.values) p: share(total - failed[p]!),
    };
    final inFrameShare = share(inFrame);

    QualityProblem? worst;
    for (final p in QualityProblem.values) {
      if (pass[p]! < config.minCheckPassShare &&
          (worst == null || pass[p]! < pass[worst]!)) {
        worst = p;
      }
    }
    final failure = tooShort
        ? SummaryFailure.tooShort
        : inFrameShare < config.minInFrameShare
            ? SummaryFailure.outOfFrame
            : worst != null
                ? SummaryFailure.problem
                : null;
    return QualitySummary._(
      measured: true,
      durationMs: durationMs,
      inFrameShare: inFrameShare,
      passShare: pass,
      failure: failure,
      worstProblem: worst,
    );
  }

  /// For the backend/ML team. Not added to the upload payload: that needs a
  /// backend agreement first.
  Map<String, Object?> toJson() => {
        'measured': measured,
        'durationMs': durationMs,
        'inFrameShare': inFrameShare,
        'passShare': {for (final e in passShare.entries) e.key.name: e.value},
        'passes': passes,
        if (failure != null) 'failure': failure!.name,
      };
}
