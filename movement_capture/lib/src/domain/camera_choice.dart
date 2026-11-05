import 'package:camera/camera.dart';

import 'usb_video_device.dart';

enum CameraKind { external, front, back }

/// What opens the camera.
enum CameraBackend { plugin, usbDirect }

/// One selectable camera, with what's needed to label it.
class CameraChoice {
  const CameraChoice({
    this.description,
    required this.kind,
    required this.ordinal,
    required this.countOfKind,
    this.backend = CameraBackend.plugin,
    this.usbDeviceName,
    this.vendorId,
    this.productId,
    this.label,
  }) : assert(
          backend == CameraBackend.usbDirect
              ? vendorId != null && productId != null
              : description != null,
          'plugin choices need a description; usbDirect needs vid/pid',
        );

  /// Null for [CameraBackend.usbDirect].
  final CameraDescription? description;
  final CameraBackend backend;

  /// `/dev/bus/usb/…` path (direct USB only; changes on replug).
  final String? usbDeviceName;
  final int? vendorId;
  final int? productId;

  /// USB product name, e.g. "Arducam 1080P Low Light" (direct USB only).
  final String? label;
  final CameraKind kind;

  /// 1-based position among cameras of the same kind.
  final int ordinal;

  /// How many cameras of this kind exist (labels add a number only if > 1).
  final int countOfKind;

  /// Android camera ID. Stable for built-in cameras; for USB cameras it is
  /// stable for the same port/device on most devices.
  ///
  /// Direct USB: `usb:<vid hex>:<pid hex>`, stable across replugs.
  String get id => backend == CameraBackend.usbDirect
      ? 'usb:${_hex4(vendorId!)}:${_hex4(productId!)}'
      : description!.name;

  bool get isUsbDirect => backend == CameraBackend.usbDirect;

  static String _hex4(int v) => v.toRadixString(16).padLeft(4, '0');

  bool get isExternal => kind == CameraKind.external;
}

CameraKind _kindOf(CameraLensDirection d) => switch (d) {
      CameraLensDirection.external => CameraKind.external,
      CameraLensDirection.front => CameraKind.front,
      CameraLensDirection.back => CameraKind.back,
    };

/// Orders cameras as: USB cameras, then front, then back. Plugin order is kept
/// within each group.
///
/// [usbDirect] webcams are used only when the plugin lists no external camera,
/// so one webcam is never offered twice. They go first, as external cameras.
List<CameraChoice> buildCameraChoices(
  List<CameraDescription> cameras, [
  List<UsbVideoDevice> usbDirect = const [],
]) {
  final result = <CameraChoice>[];
  final pluginHasExternal =
      cameras.any((c) => c.lensDirection == CameraLensDirection.external);
  if (!pluginHasExternal) {
    for (var i = 0; i < usbDirect.length; i++) {
      final d = usbDirect[i];
      result.add(CameraChoice(
        kind: CameraKind.external,
        ordinal: i + 1,
        countOfKind: usbDirect.length,
        backend: CameraBackend.usbDirect,
        usbDeviceName: d.deviceName,
        vendorId: d.vendorId,
        productId: d.productId,
        label: d.productName,
      ));
    }
  }
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

/// Picks the camera to open.
///
/// 1. [sessionChoiceId]: a camera the operator chose in this session (or a
///    deliberate per-step choice) is kept while it is still present.
/// 2. If any USB camera is connected, [preferredId] is used only when it is a
///    USB camera; otherwise the first USB camera. A saved tablet camera must
///    not hide the USB camera, which is the core capture setup.
/// 3. Otherwise [preferredId] if present, then front, then back.
///
/// Null only if [choices] is empty.
CameraChoice? pickDefaultCamera(
  List<CameraChoice> choices, {
  String? preferredId,
  String? sessionChoiceId,
}) {
  if (choices.isEmpty) return null;
  CameraChoice? byId(String? id) {
    if (id == null) return null;
    for (final c in choices) {
      if (c.id == id) return c;
    }
    return null;
  }

  final session = byId(sessionChoiceId);
  if (session != null) return session;

  final preferred = byId(preferredId);
  final hasUsb = choices.any((c) => c.isExternal);
  if (preferred != null && (!hasUsb || preferred.isExternal)) return preferred;

  for (final kind in CameraKind.values) {
    for (final c in choices) {
      if (c.kind == kind) return c;
    }
  }
  return choices.first;
}

/// Rotation handed to ML Kit so the analysed frame matches the preview on
/// screen. [configRotation] (when set) overrides everything. iOS: 0, because
/// the plugin already rotates its frames to the screen. Android: the rule
/// `CameraPreview` and the camera service apply to the preview, for front,
/// back and USB cameras alike.
int analysisRotationDegrees({
  required CameraKind kind,
  required int sensorOrientation,
  required int screenDegrees,
  int? configRotation,
  bool isIOS = false,
}) {
  if (configRotation != null) return configRotation;
  if (isIOS) return 0;
  return kind == CameraKind.front
      ? (sensorOrientation + screenDegrees) % 360
      : (sensorOrientation - screenDegrees + 360) % 360;
}
