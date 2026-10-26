import 'dart:ui' show Size;

import 'capture_step.dart';
import 'face_snapshot.dart';
import 'pose_topology.dart';

/// Collects tracking samples during one recording and turns them into the
/// landmarks.json document (format version 1).
///
/// Coordinates are normalised to the upright image. When the video file is
/// mirrored (iOS front camera) the coordinates are mirrored with it, and
/// `image.mirrored` says so.
class LandmarkTrack {
  LandmarkTrack({required this.sessionId, required this.step});

  static const String format = 'movement_capture.landmarks';
  static const int version = 1;

  final String sessionId;
  final CaptureStep step;
  final List<Map<String, Object?>> _frames = [];
  Size? _image;
  int? _rotation;

  bool get isEmpty => _frames.isEmpty;
  int get length => _frames.length;

  /// fullBody step: all pose points, grouped by region. Every region key is
  /// present, and empty when no person was found.
  void addPose({
    required int tMs,
    required List<PosePoint> pose,
    required int faceCount,
    required Size image,
    required int rotationDegrees,
  }) {
    _image ??= image;
    _rotation ??= rotationDegrees;
    final regions = <String, Map<String, Object?>>{
      for (final r in BodyRegion.values) r.name: <String, Object?>{},
    };
    for (final p in pose) {
      regions[p.region.name]![p.type.name] = [_r(p.x), _r(p.y), _r(p.likelihood)];
    }
    _frames.add({'t': tMs, 'faces': faceCount, 'regions': regions});
  }

  /// face step: the single face's box, head angles, landmarks and contours.
  /// [face] is null in frames where no single face was found.
  void addFace({
    required int tMs,
    required FaceSnapshot? face,
    required int faceCount,
    required Size image,
    required int rotationDegrees,
  }) {
    _image ??= image;
    _rotation ??= rotationDegrees;
    _frames.add({
      't': tMs,
      'faces': faceCount,
      if (face != null)
        'face': {
          'box': [
            _r(face.box.left),
            _r(face.box.top),
            _r(face.box.right),
            _r(face.box.bottom),
          ],
          'headEuler': [
            _angle(face.headEulerX),
            _angle(face.headEulerY),
            _angle(face.headEulerZ),
          ],
          'landmarks': {
            for (final e in face.landmarks.entries)
              e.key: [_r(e.value.dx), _r(e.value.dy)],
          },
          'contours': {
            for (final e in face.contours.entries)
              e.key: [
                for (final p in e.value) [_r(p.dx), _r(p.dy)],
              ],
          },
        },
    });
  }

  Map<String, Object?> toJson({required bool mirrored}) => {
        'format': format,
        'version': version,
        'sessionId': sessionId,
        'step': step.name,
        'image': {
          'width': _image?.width.round(),
          'height': _image?.height.round(),
          'rotationDegrees': _rotation,
          'mirrored': mirrored,
        },
        'sampleCount': _frames.length,
        'frames': _frames,
      };

  /// Four decimals is finer than one pixel on any camera we support.
  static double _r(double v) => (v * 10000).roundToDouble() / 10000;
  static double? _angle(double? v) =>
      v == null ? null : (v * 10).roundToDouble() / 10;
}
