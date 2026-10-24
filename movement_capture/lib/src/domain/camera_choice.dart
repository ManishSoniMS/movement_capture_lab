import 'package:camera/camera.dart';

enum CameraKind { external, front, back }

/// One selectable camera, with what's needed to label it.
class CameraChoice {
  const CameraChoice({
    required this.description,
    required this.kind,
    required this.ordinal,
    required this.countOfKind,
  });

  final CameraDescription description;
  final CameraKind kind;

  /// 1-based position among cameras of the same kind.
  final int ordinal;

  /// How many cameras of this kind exist (labels add a number only if > 1).
  final int countOfKind;

  /// Android camera ID. Stable for built-in cameras; for USB cameras it is
  /// stable for the same port/device on most devices.
  String get id => description.name;

  bool get isExternal => kind == CameraKind.external;
}

CameraKind _kindOf(CameraLensDirection d) => switch (d) {
      CameraLensDirection.external => CameraKind.external,
      CameraLensDirection.front => CameraKind.front,
      CameraLensDirection.back => CameraKind.back,
    };

/// Orders cameras as: USB cameras, then front, then back. Plugin order is kept
/// within each group.
List<CameraChoice> buildCameraChoices(List<CameraDescription> cameras) {
  final result = <CameraChoice>[];
  for (final kind in CameraKind.values) {
    final ofKind =
        cameras.where((c) => _kindOf(c.lensDirection) == kind).toList();
    for (var i = 0; i < ofKind.length; i++) {
      result.add(CameraChoice(
        description: ofKind[i],
        kind: kind,
        ordinal: i + 1,
        countOfKind: ofKind.length,
      ));
    }
  }
  return result;
}

/// The preferred camera if it is still present; otherwise the first USB
/// camera; otherwise front; otherwise back. Null only if [choices] is empty.
CameraChoice? pickDefaultCamera(
  List<CameraChoice> choices, {
  String? preferredId,
}) {
  if (choices.isEmpty) return null;
  if (preferredId != null) {
    for (final c in choices) {
      if (c.id == preferredId) return c;
    }
  }
  for (final kind in CameraKind.values) {
    for (final c in choices) {
      if (c.kind == kind) return c;
    }
  }
  return choices.first;
}

/// Rotation handed to ML Kit. A USB camera does not rotate with the tablet, so
/// it uses the fixed [configRotation]. Tablet cameras use the standard ML Kit
/// rule from sensor orientation and the current screen rotation.
int analysisRotationDegrees({
  required CameraKind kind,
  required int sensorOrientation,
  required int screenDegrees,
  required int configRotation,
}) {
  if (kind == CameraKind.external) return configRotation;
  return kind == CameraKind.front
      ? (sensorOrientation + screenDegrees) % 360
      : (sensorOrientation - screenDegrees + 360) % 360;
}
