/// Settings that must survive an app restart.
abstract interface class SettingsStore {
  /// Defaults to true (details shown) when nothing was saved.
  Future<bool> loadShowCameraDetails();
  Future<void> saveShowCameraDetails(bool value);

  /// "Stop recording if out of frame". Defaults to false when nothing was
  /// saved.
  Future<bool> loadStopWhenOutOfFrame();
  Future<void> saveStopWhenOutOfFrame(bool value);
}
