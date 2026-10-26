import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'data/file_capture_storage.dart';
import 'data/native_bridge.dart';
import 'data/support_checker.dart';
import 'domain/config.dart';
import 'domain/result.dart';
import 'domain/support_report.dart';
import 'domain/uploader.dart';
import 'presentation/customization.dart';
import 'presentation/screen.dart';

abstract final class MovementCapture {
  /// Checks whether this device and app build can run the capture.
  /// Never throws. Call it before offering the feature; show the feature only
  /// when `report.canRun` is true.
  static Future<SupportReport> checkSupport({
    SupportRequirements requirements = const SupportRequirements(),
  }) =>
      SupportChecker.run(requirements);

  /// Runs the support check, then opens the capture screen if allowed.
  /// Never returns null; see [MovementCaptureResult.status].
  ///
  /// [onCameraChanged] fires only when the operator picks a camera from the
  /// list (never on automatic fallback). Keep `camera.name` in memory and pass
  /// it back as `MovementCaptureConfig.preferredCameraId` next time.
  static Future<MovementCaptureResult> open(
    BuildContext context, {
    required MovementCaptureConfig config,
    required MovementUploader uploader,
    MovementCaptureStrings strings = const MovementCaptureStrings(),
    MovementCaptureIcons icons = const MovementCaptureIcons(),
    MovementCaptureStyle style = const MovementCaptureStyle(),
    SupportRequirements requirements = const SupportRequirements(),
    bool showDebugOverlay = false,
    void Function(CameraDescription camera)? onCameraChanged,
  }) async {
    final report = await checkSupport(requirements: requirements);
    if (!report.canRun) {
      debugPrint(report.describe());
      return MovementCaptureResult.unsupported(report);
    }
    if (!context.mounted) return MovementCaptureResult.cancelled(report);
    final result = await Navigator.of(context).push<MovementCaptureResult>(
      MaterialPageRoute(
        builder: (_) => MovementCaptureScreen(
          config: config,
          uploader: uploader,
          support: report,
          strings: strings,
          icons: icons,
          style: style,
          showDebugOverlay: showDebugOverlay,
          onCameraChanged: onCameraChanged,
        ),
      ),
    );
    return result ?? MovementCaptureResult.cancelled(report);
  }

  /// Opens this app's page in the system Settings (e.g. to allow the camera).
  static Future<bool> openAppSettings() => NativeBridge.openAppSettings();

  /// Deletes every capture file. Hosts call this on logout and before login.
  /// Never call while a capture screen is open.
  static Future<void> purgeAll() => const FileCaptureStorage().purgeAll();

  /// For diagnostics screens.
  static Future<List<CameraDescription>> listCameras() => availableCameras();
}
