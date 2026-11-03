import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guard: API 33+ package-manager flag classes crash Android < 13 with
/// NoClassDefFoundError (an Error, not an Exception) unless gated.
void main() {
  final src = File('android/app/src/main/kotlin/com/medpredict/'
          'movement_capture_lab/MainActivity.kt')
      .readAsStringSync();

  test('API 33 flag classes are gated by TIRAMISU in the same function', () {
    final flagUse =
        RegExp(r'(ApplicationInfoFlags|PackageInfoFlags|ComponentInfoFlags)');
    final funs = src.split(RegExp(r'\n\s*(?:private |override )?fun '));
    for (final body in funs.skip(1)) {
      if (flagUse.hasMatch(body)) {
        expect(body.contains('TIRAMISU'), isTrue,
            reason: 'flag class used without a TIRAMISU check in:\n'
                '${body.split('\n').first}');
      }
    }
  });

  test('channel handlers catch Throwable, not only Exception', () {
    expect(RegExp(r'catch \(e: Exception\)').hasMatch(src), isFalse);
  });
}
