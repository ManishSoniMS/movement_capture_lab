import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/movement_capture.dart';
import 'package:movement_capture/src/domain/review_samples.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  test('showSkeletonInReview defaults to false and can be set', () {
    expect(MovementCaptureConfig().showSkeletonInReview, isFalse);
    expect(
        MovementCaptureConfig(showSkeletonInReview: true).showSkeletonInReview,
        isTrue);
  });

  test('reviewShowsMarks needs both switches', () {
    bool f(bool live, bool review) => reviewShowsMarks(MovementCaptureConfig(
        showSkeleton: live, showSkeletonInReview: review));
    expect(f(false, false), isFalse);
    expect(f(true, false), isFalse);
    expect(f(false, true), isFalse);
    expect(f(true, true), isTrue);
  });

  test('review view decides on the marks through reviewShowsMarks', () {
    final view = _src('lib/src/presentation/review_view.dart');
    expect(view, contains('reviewShowsMarks('));
    expect(view, isNot(contains('config.showSkeleton &&')));
  });

  test('controller collects review samples only when the review shows them',
      () {
    final c = _src('lib/src/presentation/controller.dart');
    final add = c.indexOf('_reviewSamples.add(');
    expect(add, greaterThan(0));
    final before = c.substring(add - 200, add);
    expect(before, contains('reviewShowsMarks(config)'));
  });

  test('nothing in lib/ can composite marks into a recording', () {
    const banned = [
      'RepaintBoundary.toImage',
      'toImage(',
      'MediaMuxer',
      'MediaCodec',
    ];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.kt'));
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final b in banned) {
        expect(text, isNot(contains(b)), reason: '${f.path} uses $b');
      }
    }
  });

  test('README states the video never contains marks', () {
    expect(_src('README.md'),
        contains('The recorded video never contains tracking marks.'));
  });
}
