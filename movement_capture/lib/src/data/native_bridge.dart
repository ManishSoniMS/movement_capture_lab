import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/frame_downscaler.dart';
import '../domain/hand_topology.dart';
import '../domain/native_support_info.dart';
import '../domain/usb_video_device.dart';

/// The only Dart code that talks to the plugin's native side.
abstract final class NativeBridge {
  static const MethodChannel _channel =
      MethodChannel('movement_capture/native');

  static Future<NativeSupportInfo> supportInfo() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('supportInfo');
    return NativeSupportInfo.fromMap(raw ?? const {});
  }

  /// Opens this app's page in the system Settings. Never throws.
  static Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (e) {
      debugPrint('movement_capture: openAppSettings failed: $e');
      return false;
    }
  }

  /// Keeps the display awake while capturing. Never throws.
  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'on': on});
    } catch (e) {
      debugPrint('movement_capture: setKeepScreenOn failed: $e');
    }
  }

  /// Loads the hand model once. Never throws.
  static Future<bool> handTrackingAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('handTrackingAvailable') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Throws on failure; the analyzer handles it.
  static Future<List<HandSnapshot>> detectHands(RgbaFrame frame) async {
    final raw = await _channel.invokeListMethod<Object?>('detectHands', {
      'rgba': frame.bytes,
      'width': frame.width,
      'height': frame.height,
    });
    return [
      for (final h in raw ?? const [])
        if (h is Map) HandSnapshot.fromNative(h.cast<Object?, Object?>()),
    ];
  }

  /// Releases the hand model. Never throws.
  static Future<void> closeHands() async {
    try {
      await _channel.invokeMethod<void>('closeHands');
    } catch (_) {}
  }

  // ------------------------------------------------------------ direct USB

  static const EventChannel _usbFrames =
      EventChannel('movement_capture/usb_frames');
  static const EventChannel _usbEvents =
      EventChannel('movement_capture/usb_events');

  /// `{bytes, width, height, tMs}` maps, NV21.
  static Stream<dynamic> get usbFrames => _usbFrames.receiveBroadcastStream();

  /// `{type: attached|detached|error|noFrames, ...}` maps.
  static Stream<dynamic> get usbEvents => _usbEvents.receiveBroadcastStream();

  /// Video-class USB devices. Empty when the native library is missing.
  /// Never throws.
  static Future<List<UsbVideoDevice>> usbList() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('usbList');
      return [
        for (final d in raw ?? const [])
          if (d is Map) UsbVideoDevice.fromMap(d.cast<Object?, Object?>()),
      ];
    } catch (e) {
      debugPrint('movement_capture: usbList failed: $e');
      return const [];
    }
  }

  /// False when the direct-USB native library cannot load. Never throws.
  static Future<bool> usbDirectAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('usbDirectAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// "granted", "denied" or "cameraPermissionMissing". Never throws.
  static Future<String> usbRequestPermission(String deviceName) async {
    try {
      return await _channel.invokeMethod<String>(
              'usbRequestPermission', {'deviceName': deviceName}) ??
          'denied';
    } catch (e) {
      debugPrint('movement_capture: usbRequestPermission failed: $e');
      return 'denied';
    }
  }

  /// Throws [PlatformException] on failure.
  static Future<Map<Object?, Object?>> usbOpen({
    required String deviceName,
    required int width,
    required int height,
    required int analysisIntervalMs,
    required String previewSurface,
  }) async =>
      await _channel.invokeMapMethod<Object?, Object?>('usbOpen', {
        'deviceName': deviceName,
        'width': width,
        'height': height,
        'analysisIntervalMs': analysisIntervalMs,
        'previewSurface': previewSurface,
      }) ??
      const {};

  static Future<void> usbStartStream() =>
      _channel.invokeMethod<void>('usbStartStream');

  static Future<void> usbStopStream() async {
    try {
      await _channel.invokeMethod<void>('usbStopStream');
    } catch (_) {}
  }

  /// Backpressure ack: the Dart side is ready for the next frame.
  static void usbFrameDone() {
    _channel.invokeMethod<void>('usbFrameDone').catchError((_) {});
  }

  static Future<void> usbStartRecording(String path) =>
      _channel.invokeMethod<void>('usbStartRecording', {'path': path});

  /// Returns the clip's path.
  static Future<String> usbStopRecording() async =>
      await _channel.invokeMethod<String>('usbStopRecording') ?? '';

  /// Safe to call twice. Never throws.
  static Future<void> usbClose() async {
    try {
      await _channel.invokeMethod<void>('usbClose');
    } catch (_) {}
  }

  /// Opens the camera, waits for a frame (max 3 s) and closes it. For the
  /// support check only. Returns "ok", "noFrames" or "failed".
  static Future<String> usbProbe(String deviceName) async {
    try {
      return await _channel.invokeMethod<String>(
              'usbProbe', {'deviceName': deviceName}) ??
          'failed';
    } catch (_) {
      return 'failed';
    }
  }
}
