import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'customization.dart';
import 'screen.dart';
import 'storage.dart';
import 'uploader.dart';

abstract final class MovementCapture {
  /// Opens the capture screen. Completes with the uploader's analysis id,
  /// or null if the operator cancelled.
  static Future<String?> open(
    BuildContext context, {
    required MovementCaptureConfig config,
    required MovementUploader uploader,
    MovementCaptureStrings strings = const MovementCaptureStrings(),
    MovementCaptureIcons icons = const MovementCaptureIcons(),
    MovementCaptureStyle style = const MovementCaptureStyle(),
    bool showDebugOverlay = false,
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
        ),
      ),
    );
  }

  /// Deletes every capture file. Hosts call this on logout and before login.
  /// Never call while a capture screen is open.
  static Future<void> purgeAll() => MovementCaptureStorage.purgeAll();

  /// For diagnostics screens.
  static Future<List<CameraDescription>> listCameras() => availableCameras();
}
