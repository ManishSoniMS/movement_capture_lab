import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';

/// The README config table must list these keys with the real defaults.
void main() {
  final readme = File('README.md').readAsStringSync();
  String row(String key) => readme
      .split('\n')
      .firstWhere((l) => l.startsWith('| `$key`'), orElse: () => '');

  test('README table matches the marks and out-of-frame defaults', () {
    final c = MovementCaptureConfig();
    expect(row('showSkeleton'), contains('`true`'));
    expect(c.showSkeleton, isTrue);
    expect(
        row('skeletonMinLikelihood'), contains('${c.skeletonMinLikelihood}'));
    expect(row('stopWhenOutOfFrame'), contains('`false`'));
    expect(c.stopWhenOutOfFrame, isFalse);
    expect(row('outOfFrameStopAfter'),
        contains('${c.outOfFrameStopAfter.inSeconds} s'));
    expect(row('outOfFrameStopAfter'), contains('unconfirmed'));
  });
}
