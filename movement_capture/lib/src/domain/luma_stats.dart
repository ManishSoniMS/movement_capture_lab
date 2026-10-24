import 'dart:typed_data';

import 'capture_issue.dart';
import 'config.dart';

/// Brightness statistics from a camera frame (NV21 or BGRA), sampled every few pixels.
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

  /// Android NV21: the first `height` rows of the buffer are the brightness
  /// (Y) plane, with `bytesPerRow` bytes per row. Samples every [step]th pixel.
  factory LumaStats.fromLumaPlane(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    int step = 8,
  }) {
    final acc = _Accumulator(width, height);
    for (var y = 0; y < height; y += step) {
      final row = y * bytesPerRow;
      for (var x = 0; x < width; x += step) {
        final i = row + x;
        if (i >= bytes.length) break;
        acc.add(x, y, bytes[i]);
      }
    }
    return acc.build();
  }

  /// iOS BGRA8888: 4 bytes per pixel (blue, green, red, alpha). Brightness is
  /// computed with the standard weights (about 0.30 R + 0.59 G + 0.11 B).
  factory LumaStats.fromBgra(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    int step = 8,
  }) {
    final acc = _Accumulator(width, height);
    for (var y = 0; y < height; y += step) {
      final row = y * bytesPerRow;
      for (var x = 0; x < width; x += step) {
        final i = row + x * 4;
        if (i + 2 >= bytes.length) break;
        final b = bytes[i], g = bytes[i + 1], r = bytes[i + 2];
        acc.add(x, y, (77 * r + 150 * g + 29 * b) >> 8);
      }
    }
    return acc.build();
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

/// The centre region is the middle 40% of the width and middle 50% of height.
class _Accumulator {
  _Accumulator(int width, int height)
      : _cx0 = (width * 0.30).round(),
        _cx1 = (width * 0.70).round(),
        _cy0 = (height * 0.25).round(),
        _cy1 = (height * 0.75).round();

  final int _cx0, _cx1, _cy0, _cy1;
  int _sum = 0, _count = 0, _clipped = 0;
  int _centerSum = 0, _centerCount = 0, _borderSum = 0, _borderCount = 0;

  void add(int x, int y, int v) {
    _sum += v;
    _count++;
    if (v <= 16 || v >= 245) _clipped++;
    if (x >= _cx0 && x < _cx1 && y >= _cy0 && y < _cy1) {
      _centerSum += v;
      _centerCount++;
    } else {
      _borderSum += v;
      _borderCount++;
    }
  }

  LumaStats build() {
    if (_count == 0) {
      return const LumaStats(mean: 0, clippedFraction: 0, centerToBorder: 1);
    }
    final centerMean = _centerCount == 0 ? 0.0 : _centerSum / _centerCount;
    final borderMean = _borderCount == 0 ? 0.0 : _borderSum / _borderCount;
    return LumaStats(
      mean: _sum / _count,
      clippedFraction: _clipped / _count,
      centerToBorder: borderMean <= 0 ? 1.0 : centerMean / borderMean,
    );
  }
}
