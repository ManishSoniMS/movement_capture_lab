import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../domain/camera_catalog.dart';
import '../domain/camera_choice.dart';
import '../domain/camera_gateway.dart';
import '../domain/config.dart';
import '../domain/usb_video_device.dart';
import 'file_capture_storage.dart';
import 'native_bridge.dart';
import 'plugin_camera_gateway.dart';
import 'usb_direct_camera_gateway.dart';

/// Lists cameras from the `camera` plugin plus, on Android, USB video devices
/// that can be opened directly.
class DefaultCameraCatalog implements CameraCatalog {
  const DefaultCameraCatalog();

  @override
  Future<List<CameraChoice>> list() async {
    final List<CameraDescription> plugin;
    try {
      plugin = await availableCameras();
    } on CameraException catch (e) {
      throw CameraGatewayException(e.description ?? e.code, code: e.code);
    }
    var usb = const <UsbVideoDevice>[];
    if (defaultTargetPlatform == TargetPlatform.android) {
      usb = await NativeBridge.usbList();
    }
    return buildCameraChoices(plugin, usb);
  }

  @override
  Future<UsbPermissionResult> requestUsbPermission(CameraChoice choice) async {
    final name = choice.usbDeviceName;
    if (name == null) return UsbPermissionResult.granted;
    return switch (await NativeBridge.usbRequestPermission(name)) {
      'granted' => UsbPermissionResult.granted,
      'cameraPermissionMissing' => UsbPermissionResult.cameraPermissionMissing,
      _ => UsbPermissionResult.denied,
    };
  }

  @override
  Future<bool> hasUsbPermission(CameraChoice choice) async {
    if (!choice.isUsbDirect) return true;
    final devices = await NativeBridge.usbList();
    for (final d in devices) {
      if (d.deviceName == choice.usbDeviceName ||
          (d.vendorId == choice.vendorId && d.productId == choice.productId)) {
        return d.hasPermission;
      }
    }
    return false;
  }
}

/// The gateway for [choice] using the plugin or direct USB.
CameraGateway defaultCameraGateway(
  CameraChoice choice,
  MovementCaptureConfig config, {
  Duration analysisInterval = const Duration(milliseconds: 200),
}) {
  if (choice.isUsbDirect) {
    return UsbDirectCameraGateway(
      deviceName: choice.usbDeviceName!,
      vendorId: choice.vendorId!,
      productId: choice.productId!,
      config: config,
      analysisInterval: analysisInterval,
      newRecordingPath: () => const FileCaptureStorage().newRecordingPath(),
    );
  }
  return PluginCameraGateway(
    choice.description!,
    config.resolution,
    isIOS: defaultTargetPlatform == TargetPlatform.iOS,
  );
}
