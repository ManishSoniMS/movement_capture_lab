import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/luma_stats.dart';

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
    expect(
        _stats(_frame((_, __) => 30)).issueFor(config), CaptureIssue.tooDark);
  });

  test('uniform bright frame is tooBright', () {
    expect(_stats(_frame((_, __) => 230)).issueFor(config),
        CaptureIssue.tooBright);
  });

  test('evenly lit frame has no issue', () {
    expect(_stats(_frame((_, __) => 120)).issueFor(config), isNull);
  });

  test('dark centre on bright surroundings is backlit', () {
    final cx0 = (_w * 0.30).round(), cx1 = (_w * 0.70).round();
    final cy0 = (_h * 0.25).round(), cy1 = (_h * 0.75).round();
    final s = _stats(_frame(
        (x, y) => (x >= cx0 && x < cx1 && y >= cy0 && y < cy1) ? 50 : 200));
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

  group('BGRA (iOS)', () {
    Uint8List bgra(int Function(int x, int y) gray, {int stride = _w * 4}) {
      final bytes = Uint8List(stride * _h);
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          final v = gray(x, y);
          final i = y * stride + x * 4;
          bytes[i] = v; // B
          bytes[i + 1] = v; // G
          bytes[i + 2] = v; // R
          bytes[i + 3] = 255; // A
        }
      }
      return bytes;
    }

    LumaStats stats(Uint8List b, {int stride = _w * 4}) =>
        LumaStats.fromBgra(b, width: _w, height: _h, bytesPerRow: stride);

    test('grey pixels give their own brightness', () {
      expect(stats(bgra((_, __) => 120)).mean, closeTo(120, 0.001));
      expect(stats(bgra((_, __) => 255)).mean, closeTo(255, 0.001));
    });

    test('dark, bright and evenly lit frames', () {
      expect(stats(bgra((_, __) => 30)).issueFor(config), CaptureIssue.tooDark);
      expect(
          stats(bgra((_, __) => 230)).issueFor(config), CaptureIssue.tooBright);
      expect(stats(bgra((_, __) => 120)).issueFor(config), isNull);
    });

    test('pure red is darker than pure white', () {
      final red = Uint8List(_w * 4 * _h);
      for (var i = 0; i < red.length; i += 4) {
        red[i + 2] = 255;
        red[i + 3] = 255;
      }
      expect(stats(red).mean, closeTo(76, 1)); // 0.30 x 255
    });

    test('respects row stride larger than width x 4', () {
      const stride = _w * 4 + 64;
      expect(stats(bgra((_, __) => 120, stride: stride), stride: stride).mean,
          closeTo(120, 0.001));
    });
  });
}
