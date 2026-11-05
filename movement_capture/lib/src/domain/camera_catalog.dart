import 'camera_choice.dart';

enum UsbPermissionResult { granted, denied, cameraPermissionMissing }

/// Lists the cameras the device offers and asks for USB access. The default
/// implementation merges the `camera` plugin's list with directly-opened USB
/// video devices; tests inject a fake.
abstract interface class CameraCatalog {
  /// Throws [CameraGatewayException] when the plugin cannot list cameras.
  Future<List<CameraChoice>> list();

  /// Asks Android for access to the USB camera behind [choice].
  Future<UsbPermissionResult> requestUsbPermission(CameraChoice choice);

  /// Whether access to [choice] is already granted (always true for plugin
  /// cameras).
  Future<bool> hasUsbPermission(CameraChoice choice);
}
