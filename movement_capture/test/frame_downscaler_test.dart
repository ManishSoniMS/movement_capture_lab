import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/frame_downscaler.dart';

/// 4 × 2 BGRA image whose red channel encodes the pixel index (0…7).
Uint8List _bgra4x2() {
  final b = Uint8List(4 * 2 * 4);
  for (var i = 0; i < 8; i++) {
    b[i * 4 + 2] = i * 10; // R
    b[i * 4 + 3] = 255;
  }
  return b;
}

List<int> _reds(RgbaFrame f) =>
    [for (var i = 0; i < f.width * f.height; i++) f.bytes[i * 4]];

void main() {
  RgbaFrame run(int rotation) => downscaleToRgba(_bgra4x2(),
      nv21: false, width: 4, height: 2, bytesPerRow: 16,
      rotationDegrees: rotation, maxSide: 100);

  // Source (index → position):   0 1 2 3
  //                              4 5 6 7
  test('rotation 0 keeps the image', () {
    final f = run(0);
    expect([f.width, f.height], [4, 2]);
    expect(_reds(f), [0, 10, 20, 30, 40, 50, 60, 70]);
  });

  test('rotation 90 turns clockwise', () {
    // 4 0
    // 5 1
    // 6 2
    // 7 3
    final f = run(90);
    expect([f.width, f.height], [2, 4]);
    expect(_reds(f), [40, 0, 50, 10, 60, 20, 70, 30]);
  });

  test('rotation 180 turns upside down', () {
    final f = run(180);
    expect(_reds(f), [70, 60, 50, 40, 30, 20, 10, 0]);
  });

  test('rotation 270 turns anticlockwise', () {
    // 3 7
    // 2 6
    // 1 5
    // 0 4
    final f = run(270);
    expect([f.width, f.height], [2, 4]);
    expect(_reds(f), [30, 70, 20, 60, 10, 50, 0, 40]);
  });

  test('BGRA channels become RGBA', () {
    final src = Uint8List.fromList([10, 20, 30, 255]); // B G R A
    final f = downscaleToRgba(src,
        nv21: false, width: 1, height: 1, bytesPerRow: 4, rotationDegrees: 0);
    expect(f.bytes.sublist(0, 4), [30, 20, 10, 255]);
  });

  test('NV21 grey stays grey', () {
    // 2 × 2 Y plane of 128, then one V/U pair of 128.
    final src = Uint8List.fromList([128, 128, 128, 128, 128, 128]);
    final f = downscaleToRgba(src,
        nv21: true, width: 2, height: 2, bytesPerRow: 2, rotationDegrees: 0);
    for (var i = 0; i < 4; i++) {
      expect(f.bytes.sublist(i * 4, i * 4 + 3), [128, 128, 128]);
    }
  });

  test('scales so the longest side is maxSide', () {
    final f = downscaleToRgba(Uint8List(1280 * 720 * 4),
        nv21: false, width: 1280, height: 720, bytesPerRow: 1280 * 4,
        rotationDegrees: 0, maxSide: 256);
    expect([f.width, f.height], [256, 144]);
    expect(f.bytes.length, 256 * 144 * 4);
  });
}
