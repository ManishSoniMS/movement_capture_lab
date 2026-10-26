import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/native_support_info.dart';

/// The only Dart code that talks to the plugin's native side.
abstract final class NativeBridge {
  static const MethodChannel _channel = MethodChannel('movement_capture/native');

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
}
