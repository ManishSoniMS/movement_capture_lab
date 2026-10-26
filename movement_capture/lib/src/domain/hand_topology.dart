import 'dart:ui' show Offset, lerpDouble;

/// MediaPipe hand point names, in model order (21 points).
const List<String> handPointNames = [
  'wrist',
  'thumbCmc', 'thumbMcp', 'thumbIp', 'thumbTip',
  'indexMcp', 'indexPip', 'indexDip', 'indexTip',
  'middleMcp', 'middlePip', 'middleDip', 'middleTip',
  'ringMcp', 'ringPip', 'ringDip', 'ringTip',
  'pinkyMcp', 'pinkyPip', 'pinkyDip', 'pinkyTip',
];

/// The standard hand skeleton (21 lines), as index pairs.
const List<(int, int)> handConnections = [
  (0, 1), (1, 2), (2, 3), (3, 4), // thumb
  (0, 5), (5, 6), (6, 7), (7, 8), // index
  (5, 9), (9, 10), (10, 11), (11, 12), // middle
  (9, 13), (13, 14), (14, 15), (15, 16), // ring
  (13, 17), (0, 17), (17, 18), (18, 19), (19, 20), // pinky + palm
];

/// One tracked hand, in normalised upright-image coordinates (0–1).
class HandSnapshot {
  const HandSnapshot({
    required this.handedness,
    required this.score,
    required this.points,
    required this.depth,
  });

  /// From the plugin: {"handedness", "score", "points": [x, y, z, …] × 21}.
  factory HandSnapshot.fromNative(Map<Object?, Object?> m) {
    final flat = (m['points'] as List?)?.cast<num>() ?? const <num>[];
    final points = <Offset>[];
    final depth = <double>[];
    for (var i = 0; i + 2 < flat.length; i += 3) {
      points.add(Offset(flat[i].toDouble(), flat[i + 1].toDouble()));
      depth.add(flat[i + 2].toDouble());
    }
    return HandSnapshot(
      handedness: (m['handedness'] as String?) ?? 'Unknown',
      score: (m['score'] as num?)?.toDouble() ?? 0,
      points: points,
      depth: depth,
    );
  }

  /// The model's own label ("Left"/"Right"), which assumes a mirrored image.
  final String handedness;
  final double score;
  final List<Offset> points;

  /// Relative depth per point (smaller = closer), as MediaPipe reports it.
  final List<double> depth;

  bool get isComplete => points.length == handPointNames.length;

  static HandSnapshot lerp(HandSnapshot a, HandSnapshot b, double t) {
    if (a.points.length != b.points.length || a.handedness != b.handedness) {
      return b;
    }
    return HandSnapshot(
      handedness: b.handedness,
      score: b.score,
      depth: b.depth,
      points: [
        for (var i = 0; i < b.points.length; i++)
          Offset(lerpDouble(a.points[i].dx, b.points[i].dx, t)!,
              lerpDouble(a.points[i].dy, b.points[i].dy, t)!),
      ],
    );
  }
}

/// The person's own side. MediaPipe labels hands as if the image were mirrored
/// (a selfie). Our frames are mirrored only for the iOS front camera.
String personSide(String handedness, {required bool framesMirrored}) {
  if (framesMirrored) return handedness.toLowerCase();
  return switch (handedness.toLowerCase()) {
    'left' => 'right',
    'right' => 'left',
    final other => other,
  };
}
