import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/luma_stats.dart';

const _w = 160, _h = 120;

Uint8List _frame(int Function(int x, int y) pixel) {
  final bytes = Uint8List(_w * _h);
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      bytes[y * _w + x] = pixel(x, y);
    }
  }
  return bytes;
}

LumaStats _stats(Uint8List b) =>
    LumaStats.fromLumaPlane(b, width: _w, height: _h, bytesPerRow: _w);

void main() {
  final config = MovementCaptureConfig();

  test('uniform dark frame is tooDark', () {
    expect(_stats(_frame((_, __) => 30)).issueFor(config), CaptureIssue.tooDark);
  });

  test('uniform bright frame is tooBright', () {
    expect(_stats(_frame((_, __) => 230)).issueFor(config), CaptureIssue.tooBright);
  });

  test('evenly lit frame has no issue', () {
    expect(_stats(_frame((_, __) => 120)).issueFor(config), isNull);
  });

  test('dark centre on bright surroundings is backlit', () {
    final cx0 = (_w * 0.30).round(), cx1 = (_w * 0.70).round();
    final cy0 = (_h * 0.25).round(), cy1 = (_h * 0.75).round();
    final s = _stats(_frame((x, y) =>
        (x >= cx0 && x < cx1 && y >= cy0 && y < cy1) ? 50 : 200));
    expect(s.mean, inInclusiveRange(60, 200)); // not caught by the mean rule
    expect(s.issueFor(config), CaptureIssue.backlit);
  });

  test('heavy clipping with a low mean is tooDark', () {
    // Sampled columns alternate between black and near-white:
    // mean ≈ 125 (passes the mean rules) but 100% of samples are clipped.
    final s = _stats(_frame((x, _) => (x ~/ 8).isEven ? 0 : 250));
    expect(s.mean, inInclusiveRange(60, 200));
    expect(s.clippedFraction, greaterThan(0.9));
    expect(s.issueFor(config), CaptureIssue.tooDark);
  });

  test('respects row stride larger than width', () {
    const stride = _w + 32;
    final bytes = Uint8List(stride * _h);
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < stride; x++) {
        bytes[y * stride + x] = x < _w ? 120 : 255; // padding must be ignored
      }
    }
    final s = LumaStats.fromLumaPlane(bytes,
        width: _w, height: _h, bytesPerRow: stride);
    expect(s.mean, closeTo(120, 0.001));
  });
}
