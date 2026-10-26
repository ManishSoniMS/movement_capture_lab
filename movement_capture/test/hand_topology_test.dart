import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/domain/hand_topology.dart';

void main() {
  test('21 named points and 21 lines within range', () {
    expect(handPointNames.length, 21);
    expect(handConnections.length, 21);
    for (final (a, b) in handConnections) {
      expect(a, inInclusiveRange(0, 20));
      expect(b, inInclusiveRange(0, 20));
    }
  });

  test('parses the plugin answer', () {
    final h = HandSnapshot.fromNative({
      'handedness': 'Left',
      'score': 0.97,
      'points': [for (var i = 0; i < 63; i++) i / 100],
    });
    expect(h.isComplete, isTrue);
    expect(h.points[1].dx, closeTo(0.03, 1e-9));
    expect(h.depth[0], closeTo(0.02, 1e-9));
  });

  test('person side swaps unless the frames are mirrored', () {
    expect(personSide('Left', framesMirrored: false), 'right');
    expect(personSide('Right', framesMirrored: false), 'left');
    expect(personSide('Left', framesMirrored: true), 'left');
    expect(personSide('Unknown', framesMirrored: false), 'unknown');
  });
}
