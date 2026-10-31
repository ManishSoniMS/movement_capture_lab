import 'pose_topology.dart';

/// One skeleton sample kept for the review, [tMs] = ms since recording start.
class TimedOverlay {
  const TimedOverlay(this.tMs, this.frame);
  final int tMs;
  final OverlayFrame frame;
}

/// The latest sample at or before [positionMs] (binary search), or null if
/// [samples] is empty or the position is before the first sample.
OverlayFrame? overlayAt(List<TimedOverlay> samples, int positionMs) {
  if (samples.isEmpty || positionMs < samples.first.tMs) return null;
  var lo = 0, hi = samples.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (samples[mid].tMs <= positionMs) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return samples[lo].frame;
}
