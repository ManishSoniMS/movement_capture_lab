import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guard for `UsbDirectCamera.kt`.
///
/// Flutter's `TextureRegistry` (create and release of a producer or texture
/// entry) calls `FlutterJNI` methods marked `@UiThread`. Calling them from the
/// camera `HandlerThread` throws at open, and at close the error is swallowed
/// so a texture leaks. Kotlin cannot be run under `flutter test`, so this
/// checks the text: those calls may only appear in a function annotated
/// `@UiThread` or inside a `main.post {` block.
void main() {
  final file = File(
      'android/src/main/kotlin/com/medpredict/movement_capture/UsbDirectCamera.kt');
  late final List<String> lines;
  setUpAll(() => lines = file.readAsLinesSync());

  /// Index of the nearest `fun` declaration at or above [i], or -1.
  int funAbove(int i) {
    for (var k = i; k >= 0; k--) {
      if (RegExp(r'^\s*(private |internal |override )*fun ').hasMatch(lines[k])) {
        return k;
      }
    }
    return -1;
  }

  bool annotatedUiThread(int funLine) {
    for (var k = funLine; k >= 0 && k >= funLine - 3; k--) {
      if (lines[k].contains('@UiThread')) return true;
      if (k < funLine && lines[k].trim().isEmpty) break;
    }
    return false;
  }

  bool insideMainPost(int i) {
    final start = funAbove(i);
    for (var k = i; k > start && k >= 0; k--) {
      if (lines[k].contains('main.post {') ||
          lines[k].contains('main.post{')) {
        return true;
      }
    }
    return false;
  }

  List<int> hits(Pattern p) => [
        for (var i = 0; i < lines.length; i++)
          if (!lines[i].trimLeft().startsWith('//') &&
              !lines[i].trimLeft().startsWith('*') &&
              lines[i].contains(p))
            i,
      ];

  void expectUiOnly(List<int> found, String what) {
    for (final i in found) {
      final f = funAbove(i);
      final ok = (f >= 0 && annotatedUiThread(f)) || insideMainPost(i);
      expect(ok, isTrue,
          reason: '$what at UsbDirectCamera.kt:${i + 1} must be in an '
              '@UiThread function or a main.post { } block');
    }
  }

  test('texture creation only on the main thread', () {
    final found = [
      ...hits('createSurfaceProducer('),
      ...hits('createSurfaceTexture('),
    ];
    expect(found, isNotEmpty);
    expectUiOnly(found, 'texture creation');
  });

  test('texture and preview-target release only on the main thread', () {
    final found = [
      ...hits(RegExp(r'\b(producer|entry|textureEntry|target|t|old)\??\.release\(\)')),
    ];
    expect(found, isNotEmpty);
    expectUiOnly(found, 'texture release');
  });

  test('camera-thread functions assert their thread', () {
    final src = lines.join('\n');
    for (final name in [
      'openCamera',
      'closeAll',
      'probe',
      'startRecording',
      'stopRecording',
    ]) {
      final m = RegExp('fun $name\\([^{]*\\{([^\\n]*\\n){1,4}').firstMatch(src);
      expect(m, isNotNull, reason: 'fun $name not found');
      expect(m!.group(0), contains('checkCameraThread()'),
          reason: '$name must start with checkCameraThread()');
    }
  });

  test('the probe does not create a Flutter texture', () {
    final src = lines.join('\n');
    final start = src.indexOf('fun probe(');
    final end = src.indexOf('fun closeAll(');
    expect(start, greaterThan(-1));
    final body = src.substring(start, end);
    expect(body, isNot(contains('createSurface')));
    expect(body, isNot(contains('PreviewTarget')));
  });
}
