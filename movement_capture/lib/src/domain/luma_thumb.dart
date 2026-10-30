import 'dart:math' as math;
import 'dart:typed_data';

/// A small greyscale copy of a camera frame (brightness only, longest side at
/// most [maxSide]), used for the sharpness and movement checks. Lives for one
/// analysis; never stored or logged.
class LumaThumb {
  const LumaThumb._(this.pixels, this.width, this.height);

  final Uint8List pixels;
  final int width;
  final int height;

  /// Android NV21: the first `height` rows of [bytes] are the Y plane.
  factory LumaThumb.fromLumaPlane(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    int maxSide = 160,
  }) =>
      _build(width, height, maxSide, (x, y) {
        final i = y * bytesPerRow + x;
        return i < bytes.length ? bytes[i] : 0;
      });

  /// iOS BGRA8888, brightness with the standard weights.
  factory LumaThumb.fromBgra(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    int maxSide = 160,
  }) =>
      _build(width, height, maxSide, (x, y) {
        final i = y * bytesPerRow + x * 4;
        if (i + 2 >= bytes.length) return 0;
        return (77 * bytes[i + 2] + 150 * bytes[i + 1] + 29 * bytes[i]) >> 8;
      });

  static LumaThumb _build(
    int width,
    int height,
    int maxSide,
    int Function(int x, int y) sample,
  ) {
    final scale = math.min(1.0, maxSide / math.max(width, height));
    final w = math.max(1, (width * scale).round());
    final h = math.max(1, (height * scale).round());
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final sy = math.min(height - 1, ((y + 0.5) / scale).floor());
      for (var x = 0; x < w; x++) {
        final sx = math.min(width - 1, ((x + 0.5) / scale).floor());
        out[y * w + x] = sample(sx, sy);
      }
    }
    return LumaThumb._(out, w, h);
  }

  /// Variance of the 4-neighbour Laplacian. High = crisp edges, low = blur.
  /// Units: squared brightness levels (0–255 scale).
  double get sharpness {
    if (width < 3 || height < 3) return 0;
    var sum = 0.0, sumSq = 0.0;
    var n = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final v = pixels[i - 1] +
            pixels[i + 1] +
            pixels[i - width] +
            pixels[i + width] -
            4 * pixels[i];
        sum += v;
        sumSq += v * v;
        n++;
      }
    }
    final mean = sum / n;
    return sumSq / n - mean * mean;
  }

  /// Mean absolute brightness difference to [previous] (0–255). Zero when
  /// there is no previous frame or its size differs (camera changed).
  double motionFrom(LumaThumb? previous) {
    if (previous == null ||
        previous.width != width ||
        previous.height != height) {
      return 0;
    }
    var sum = 0;
    for (var i = 0; i < pixels.length; i++) {
      sum += (pixels[i] - previous.pixels[i]).abs();
    }
    return sum / pixels.length;
  }
}
