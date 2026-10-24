import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/capture_state.dart';

void main() {
  test('Recording.progress is clamped to 0..1', () {
    const total = Duration(seconds: 10);
    expect(
      const Recording(elapsed: Duration(seconds: 5), total: total).progress,
      0.5,
    );
    expect(
      const Recording(elapsed: Duration(seconds: 20), total: total).progress,
      1,
    );
    expect(
      const Recording(elapsed: Duration(seconds: -1), total: total).progress,
      0,
    );
  });

  test('Recording.progress is 0 when total is zero', () {
    expect(
      const Recording(elapsed: Duration(seconds: 1), total: Duration.zero)
          .progress,
      0,
    );
  });
}
