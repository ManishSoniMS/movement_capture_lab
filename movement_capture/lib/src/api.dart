import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'data/file_capture_storage.dart';
import 'domain/config.dart';
import 'domain/uploader.dart';
import 'presentation/customization.dart';
import 'presentation/screen.dart';

abstract final class MovementCapture {
  /// Opens the capture screen. Completes with the uploader's analysis id,
  /// or null if the operator cancelled.
  ///
  /// [onCameraChanged] fires only when the operator picks a camera from the
  /// list (never on automatic fallback). Keep `camera.name` in memory and pass
  /// it back as `MovementCaptureConfig.preferredCameraId` next time.
  static Future<String?> open(
    BuildContext context, {
    required MovementCaptureConfig config,
    required MovementUploader uploader,
    MovementCaptureStrings strings = const MovementCaptureStrings(),
    MovementCaptureIcons icons = const MovementCaptureIcons(),
    MovementCaptureStyle style = const MovementCaptureStyle(),
    bool showDebugOverlay = false,
    void Function(CameraDescription camera)? onCameraChanged,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MovementCaptureScreen(
          config: config,
          uploader: uploader,
          strings: strings,
          icons: icons,
          style: style,
          showDebugOverlay: showDebugOverlay,
          onCameraChanged: onCameraChanged,
        ),
      ),
    );
  }

  /// Deletes every capture file. Hosts call this on logout and before login.
  /// Never call while a capture screen is open.
  static Future<void> purgeAll() => const FileCaptureStorage().purgeAll();

  /// For diagnostics screens.
  static Future<List<CameraDescription>> listCameras() => availableCameras();
}
