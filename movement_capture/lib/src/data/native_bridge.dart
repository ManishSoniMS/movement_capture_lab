import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/frame_downscaler.dart';
import '../domain/hand_topology.dart';
import '../domain/native_support_info.dart';

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
}
