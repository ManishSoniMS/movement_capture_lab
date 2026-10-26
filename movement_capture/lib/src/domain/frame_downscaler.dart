import 'dart:math' as math;
import 'dart:typed_data';

/// A small upright RGBA image (R, G, B, A per pixel, tightly packed).
class RgbaFrame {
  const RgbaFrame(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Converts a camera frame to a small upright RGBA image: rotated clockwise
/// by [rotationDegrees] (the same value given to ML Kit) and scaled so the
/// longest side is at most [maxSide]. Nearest-neighbour sampling.
///
/// [nv21] true: Android NV21 (Y plane, then interleaved V/U, both with
/// [bytesPerRow]). false: iOS BGRA8888.
RgbaFrame downscaleToRgba(
  Uint8List src, {
  required bool nv21,
  required int width,
  required int height,
  required int bytesPerRow,
  required int rotationDegrees,
  int maxSide = 256,
}) {
  final r = ((rotationDegrees % 360) + 360) % 360;
  final swap = r == 90 || r == 270;
  final uprightW = swap ? height : width;
  final uprightH = swap ? width : height;
  final scale = math.min(1.0, maxSide / math.max(uprightW, uprightH));
  final outW = math.max(1, (uprightW * scale).round());
  final outH = math.max(1, (uprightH * scale).round());
  final out = Uint8List(outW * outH * 4);

  final uvStart = bytesPerRow * height;
  final hasUv = nv21 && src.length >= uvStart + bytesPerRow * (height ~/ 2);

  for (var oy = 0; oy < outH; oy++) {
    final uy = math.min(uprightH - 1, ((oy + 0.5) / scale).floor());
    for (var ox = 0; ox < outW; ox++) {
      final ux = math.min(uprightW - 1, ((ox + 0.5) / scale).floor());

      // Upright pixel (ux, uy) → source pixel (sx, sy).
      int sx, sy;
      switch (r) {
        case 90:
          sx = uy;
          sy = height - 1 - ux;
        case 180:
          sx = width - 1 - ux;
          sy = height - 1 - uy;
        case 270:
          sx = width - 1 - uy;
          sy = ux;
        default:
          sx = ux;
          sy = uy;
      }

      int red, green, blue;
      if (nv21) {
        final yi = sy * bytesPerRow + sx;
        final y = yi < src.length ? src[yi] : 0;
        if (hasUv) {
          final uvi = uvStart + (sy >> 1) * bytesPerRow + (sx & ~1);
          final v = src[uvi] - 128;
          final u = src[uvi + 1] - 128;
          // BT.601 conversion, integer approximation.
          red = y + ((359 * v) >> 8);
          green = y - ((88 * u + 183 * v) >> 8);
          blue = y + ((454 * u) >> 8);
        } else {
          red = green = blue = y;
        }
      } else {
        final i = sy * bytesPerRow + sx * 4;
        if (i + 2 < src.length) {
          blue = src[i];
          green = src[i + 1];
          red = src[i + 2];
        } else {
          red = green = blue = 0;
        }
      }

      final o = (oy * outW + ox) * 4;
      out[o] = red.clamp(0, 255);
      out[o + 1] = green.clamp(0, 255);
      out[o + 2] = blue.clamp(0, 255);
      out[o + 3] = 255;
    }
  }
  return RgbaFrame(out, outW, outH);
}
