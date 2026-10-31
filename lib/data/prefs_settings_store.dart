import 'package:shared_preferences/shared_preferences.dart';

import '../domain/settings_store.dart';

/// [SettingsStore] on the device's SharedPreferences.
class PrefsSettingsStore implements SettingsStore {
  static const _showDetailsKey = 'show_camera_details';
  static const _stopOutOfFrameKey = 'stop_when_out_of_frame';

  @override
  Future<bool> loadShowCameraDetails() async =>
      (await SharedPreferences.getInstance()).getBool(_showDetailsKey) ?? true;

  @override
  Future<void> saveShowCameraDetails(bool value) async {
    await (await SharedPreferences.getInstance())
        .setBool(_showDetailsKey, value);
  }

  @override
  Future<bool> loadStopWhenOutOfFrame() async =>
      (await SharedPreferences.getInstance()).getBool(_stopOutOfFrameKey) ??
      false;

  @override
  Future<void> saveStopWhenOutOfFrame(bool value) async {
    await (await SharedPreferences.getInstance())
        .setBool(_stopOutOfFrameKey, value);
  }
}
