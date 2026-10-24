import 'dart:typed_data';

import 'capture_issue.dart';
import 'config.dart';

/// Brightness statistics from the Y (luma) plane of an NV21 frame.
class LumaStats {
  const LumaStats({
    required this.mean,
    required this.clippedFraction,
    required this.centerToBorder,
  });

  /// Average brightness, 0–255.
  final double mean;

  /// Share of sampled pixels that are nearly black (≤16) or white (≥245).
  final double clippedFraction;

  /// Centre-region brightness ÷ border-region brightness.
  final double centerToBorder;

  /// Samples every [step]th pixel in both directions. The centre region is the
  /// middle 40% of the width and the middle 50% of the height.
  factory LumaStats.fromLumaPlane(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    int step = 8,
  }) {
    final cx0 = (width * 0.30).round(), cx1 = (width * 0.70).round();
    final cy0 = (height * 0.25).round(), cy1 = (height * 0.75).round();

    var sum = 0, count = 0, clipped = 0;
    var centerSum = 0, centerCount = 0, borderSum = 0, borderCount = 0;

    for (var y = 0; y < height; y += step) {
      final row = y * bytesPerRow;
      for (var x = 0; x < width; x += step) {
        final i = row + x;
        if (i >= bytes.length) break;
        final v = bytes[i];
        sum += v;
        count++;
        if (v <= 16 || v >= 245) clipped++;
        if (x >= cx0 && x < cx1 && y >= cy0 && y < cy1) {
          centerSum += v;
          centerCount++;
        } else {
          borderSum += v;
          borderCount++;
        }
      }
    }

    if (count == 0) {
      return const LumaStats(mean: 0, clippedFraction: 0, centerToBorder: 1);
    }
    final centerMean = centerCount == 0 ? 0.0 : centerSum / centerCount;
    final borderMean = borderCount == 0 ? 0.0 : borderSum / borderCount;
    return LumaStats(
      mean: sum / count,
      clippedFraction: clipped / count,
      centerToBorder: borderMean <= 0 ? 1.0 : centerMean / borderMean,
    );
  }

  /// At most one lighting issue per frame.
  CaptureIssue? issueFor(MovementCaptureConfig c) {
    if (mean < c.minMeanLuma) return CaptureIssue.tooDark;
    if (mean > c.maxMeanLuma) return CaptureIssue.tooBright;
    if (clippedFraction > c.maxClippedFraction) {
      return mean < 128 ? CaptureIssue.tooDark : CaptureIssue.tooBright;
    }
    if (centerToBorder < c.minCenterToBorderLuma) return CaptureIssue.backlit;
    return null;
  }
}
